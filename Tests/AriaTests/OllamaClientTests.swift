import XCTest
@testable import aria_capture

final class OllamaClientTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testChatEndpointTrimsTrailingSlash() {
        XCTAssertEqual(
            OllamaClient.chatEndpoint(baseURL: "http://localhost:11434/")?.absoluteString,
            "http://localhost:11434/api/chat"
        )
    }

    func testTagsEndpoint() {
        XCTAssertEqual(
            OllamaClient.tagsEndpoint(baseURL: "http://localhost:11434")?.absoluteString,
            "http://localhost:11434/api/tags"
        )
    }

    func testRequestBodyMapsMaxTokensToNumPredict() {
        let body = OllamaClient.requestBody(system: "sys", userMessage: "hola", model: "llama3", maxTokens: 500)
        XCTAssertEqual(body["model"] as? String, "llama3")
        XCTAssertEqual(body["stream"] as? Bool, true)
        let options = body["options"] as? [String: Int]
        XCTAssertEqual(options?["num_predict"], 500)
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?[0]["role"], "system")
        XCTAssertEqual(messages?[1]["role"], "user")
    }

    func testInitFallsBackToDefaultBaseURL() throws {
        let client = try OllamaClient(baseURL: "", model: "llama3")
        XCTAssertEqual(client.baseURL, OllamaClient.defaultBaseURL)
    }

    func testInitThrowsOnMissingModel() {
        XCTAssertThrowsError(try OllamaClient(baseURL: "http://localhost:11434", model: ""))
    }

    func testParseModelNamesSorted() {
        let json = """
        {"models":[{"name":"mistral"},{"name":"llama3:8b"}]}
        """
        let names = OllamaClient.parseModelNames(Data(json.utf8))
        XCTAssertEqual(names, ["llama3:8b", "mistral"])
    }

    func testParseModelNamesEmptyOnMalformedJSON() {
        XCTAssertEqual(OllamaClient.parseModelNames(Data("not json".utf8)), [])
    }

    func testCompleteParsesNDJSONStreamAndFinalCounts() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let line1 = "{\"message\":{\"role\":\"assistant\",\"content\":\"Hola\"},\"done\":false}\n"
            let line2 = "{\"message\":{\"role\":\"assistant\",\"content\":\" mundo\"},\"done\":false}\n"
            let line3 = "{\"message\":{\"role\":\"assistant\",\"content\":\"\"},\"done\":true,\"prompt_eval_count\":12,\"eval_count\":7}\n"
            return (response, [Data(line1.utf8), Data(line2.utf8), Data(line3.utf8)])
        }
        let client = try OllamaClient(baseURL: "http://localhost:11434", model: "llama3", session: MockURLProtocol.makeSession())
        var chunks: [String] = []
        let result = try await client.complete(system: "sys", userMessage: "hi", maxTokens: 100) { chunks.append($0) }
        XCTAssertEqual(result.text, "Hola mundo")
        XCTAssertEqual(result.inputTokens, 12)
        XCTAssertEqual(result.outputTokens, 7)
        XCTAssertEqual(chunks, ["Hola", " mundo"])
    }

    func testCompleteSendsExpectedRequest() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { request in
            captured = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, [Data("{\"message\":{\"content\":\"ok\"},\"done\":true}\n".utf8)])
        }
        let client = try OllamaClient(baseURL: "http://localhost:11434", model: "llama3", session: MockURLProtocol.makeSession())
        _ = try await client.complete(system: "sys", userMessage: "hi", maxTokens: 10)
        XCTAssertEqual(captured?.url?.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertEqual(captured?.httpMethod, "POST")
        let bodyData = MockURLProtocol.bodyData(from: captured!)
        let bodyJSON = try JSONSerialization.jsonObject(with: bodyData!) as? [String: Any]
        XCTAssertEqual(bodyJSON?["model"] as? String, "llama3")
    }

    func testCompleteThrowsOnHTTPError() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, [Data("{\"error\":\"model 'llama3' not found\"}".utf8)])
        }
        let client = try OllamaClient(baseURL: "http://localhost:11434", model: "llama3", session: MockURLProtocol.makeSession())
        do {
            _ = try await client.complete(system: "sys", userMessage: "hi", maxTokens: 10)
            XCTFail("Se esperaba error")
        } catch let error as OllamaError {
            XCTAssertEqual(error.errorDescription, "Ollama HTTP 404: model 'llama3' not found")
        }
    }

    func testCompleteIgnoresBlankLines() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = "\n{\"message\":{\"content\":\"ok\"},\"done\":false}\n\n{\"done\":true,\"eval_count\":1,\"prompt_eval_count\":2}\n"
            return (response, [Data(body.utf8)])
        }
        let client = try OllamaClient(baseURL: "http://localhost:11434", model: "llama3", session: MockURLProtocol.makeSession())
        let result = try await client.complete(system: "sys", userMessage: "hi", maxTokens: 10)
        XCTAssertEqual(result.text, "ok")
        XCTAssertEqual(result.inputTokens, 2)
        XCTAssertEqual(result.outputTokens, 1)
    }

    func testListModelsReturnsNamesFromTagsEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/tags")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = "{\"models\":[{\"name\":\"llama3:8b\"}]}"
            return (response, [Data(body.utf8)])
        }
        let names = try await OllamaClient.listModels(baseURL: "http://localhost:11434", session: MockURLProtocol.makeSession())
        XCTAssertEqual(names, ["llama3:8b"])
    }
}
