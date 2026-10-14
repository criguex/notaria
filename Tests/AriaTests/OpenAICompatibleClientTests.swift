import XCTest
@testable import aria_capture

final class OpenAICompatibleClientTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testEndpointAppendsChatCompletions() {
        XCTAssertEqual(
            OpenAICompatibleClient.endpoint(baseURL: "https://api.openai.com/v1")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
    }

    func testEndpointStripsTrailingSlash() {
        XCTAssertEqual(
            OpenAICompatibleClient.endpoint(baseURL: "https://api.groq.com/openai/v1/")?.absoluteString,
            "https://api.groq.com/openai/v1/chat/completions"
        )
    }

    func testEndpointDoesNotDuplicateSuffix() {
        XCTAssertEqual(
            OpenAICompatibleClient.endpoint(baseURL: "http://localhost:1234/v1/chat/completions")?.absoluteString,
            "http://localhost:1234/v1/chat/completions"
        )
    }

    func testEndpointNilForEmptyBaseURL() {
        XCTAssertNil(OpenAICompatibleClient.endpoint(baseURL: ""))
        XCTAssertNil(OpenAICompatibleClient.endpoint(baseURL: "/"))
    }

    func testModelsEndpoint() {
        XCTAssertEqual(
            OpenAICompatibleClient.modelsEndpoint(baseURL: "https://api.openai.com/v1/")?.absoluteString,
            "https://api.openai.com/v1/models"
        )
    }

    func testRequestBodyShape() {
        let body = OpenAICompatibleClient.requestBody(
            system: "sys", userMessage: "hola", model: "gpt-4o-mini", maxTokens: 123
        )
        XCTAssertEqual(body["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(body["max_tokens"] as? Int, 123)
        XCTAssertEqual(body["stream"] as? Bool, true)
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?[0]["role"], "system")
        XCTAssertEqual(messages?[0]["content"], "sys")
        XCTAssertEqual(messages?[1]["role"], "user")
        XCTAssertEqual(messages?[1]["content"], "hola")
    }

    func testInitThrowsOnMissingBaseURLOrModel() {
        XCTAssertThrowsError(try OpenAICompatibleClient(baseURL: "", model: "gpt-4o-mini", apiKey: nil))
        XCTAssertThrowsError(try OpenAICompatibleClient(baseURL: "https://api.openai.com/v1", model: "", apiKey: nil))
    }

    func testCompleteStreamsTextAcrossChunksAndParsesUsage() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { request in
            captured = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let chunk1 = "data: {\"choices\":[{\"delta\":{\"content\":\"Hola\"}}]}\n\n"
            let chunk2 = "data: {\"choices\":[{\"delta\":{\"content\":\" mundo\"}}]}\n\n"
            let chunk3 = "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}\n\ndata: [DONE]\n\n"
            return (response, [Data(chunk1.utf8), Data(chunk2.utf8), Data(chunk3.utf8)])
        }
        let client = try OpenAICompatibleClient(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            apiKey: "sk-test",
            session: MockURLProtocol.makeSession()
        )
        var chunks: [String] = []
        let result = try await client.complete(system: "sys", userMessage: "hi", maxTokens: 999) { chunks.append($0) }
        XCTAssertEqual(result.text, "Hola mundo")
        XCTAssertEqual(result.inputTokens, 10)
        XCTAssertEqual(result.outputTokens, 5)
        XCTAssertEqual(result.stopReason, "stop")
        XCTAssertEqual(chunks, ["Hola", " mundo"])
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(captured?.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testCompleteOmitsAuthorizationHeaderWithoutKey() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { request in
            captured = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, [Data("data: [DONE]\n\n".utf8)])
        }
        let client = try OpenAICompatibleClient(
            baseURL: "http://localhost:1234/v1",
            model: "local-model",
            apiKey: nil,
            session: MockURLProtocol.makeSession()
        )
        _ = try await client.complete(system: "sys", userMessage: "hi", maxTokens: 10)
        XCTAssertNil(captured?.value(forHTTPHeaderField: "Authorization"))
    }

    func testCompleteSplitLineAcrossChunksStillParses() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let full = "data: {\"choices\":[{\"delta\":{\"content\":\"partido\"}}]}\n\ndata: [DONE]\n\n"
            let data = Data(full.utf8)
            let splitPoint = full.utf8.count / 2
            return (response, [data.prefix(splitPoint), data.suffix(from: splitPoint)])
        }
        let client = try OpenAICompatibleClient(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            apiKey: nil,
            session: MockURLProtocol.makeSession()
        )
        let result = try await client.complete(system: "sys", userMessage: "hi", maxTokens: 10)
        XCTAssertEqual(result.text, "partido")
    }

    func testCompleteThrowsOnHTTPErrorWithParsedMessage() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            let body = "{\"error\":{\"message\":\"Invalid API key\",\"type\":\"invalid_request_error\"}}"
            return (response, [Data(body.utf8)])
        }
        let client = try OpenAICompatibleClient(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            apiKey: "bad-key",
            session: MockURLProtocol.makeSession()
        )
        do {
            _ = try await client.complete(system: "sys", userMessage: "hi", maxTokens: 10)
            XCTFail("Se esperaba error")
        } catch let error as OpenAICompatibleError {
            XCTAssertEqual(error.errorDescription, "OpenAI-compatible HTTP 401: Invalid API key")
        }
    }

    func testCompleteIgnoresMalformedLines() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = "data: not-json\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n"
            return (response, [Data(body.utf8)])
        }
        let client = try OpenAICompatibleClient(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            apiKey: nil,
            session: MockURLProtocol.makeSession()
        )
        let result = try await client.complete(system: "sys", userMessage: "hi", maxTokens: 10)
        XCTAssertEqual(result.text, "ok")
    }

    func testBackendNameIncludesModelAndBaseURL() throws {
        let client = try OpenAICompatibleClient(baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", apiKey: nil)
        XCTAssertTrue(client.backendName.contains("gpt-4o-mini"))
        XCTAssertTrue(client.backendName.contains("https://api.openai.com/v1"))
    }
}
