import XCTest
@testable import aria_capture

final class AIProviderTesterTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func config(_ provider: AIProviderKind, baseURL: String = "", model: String = "") -> AriaConfig {
        var config = AriaConfig()
        config.aiProvider = provider
        config.aiBaseURL = baseURL
        config.aiModel = model
        return config
    }

    func testAnthropicAPIMissingKeyFailsWithoutNetworkCall() async {
        var networkCalled = false
        MockURLProtocol.handler = { request in
            networkCalled = true
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, [])
        }
        let result = await AIProviderTester.test(
            config: config(.anthropicAPI),
            session: MockURLProtocol.makeSession(),
            anthropicKeyProvider: { nil }
        )
        XCTAssertFalse(result.ok)
        XCTAssertFalse(networkCalled)
        XCTAssertTrue(result.message.contains("Keychain"))
    }

    func testAnthropicAPISuccessWithMockedKeyAndSession() async {
        var captured: URLRequest?
        MockURLProtocol.handler = { request in
            captured = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, [Data()])
        }
        let result = await AIProviderTester.test(
            config: config(.anthropicAPI),
            session: MockURLProtocol.makeSession(),
            anthropicKeyProvider: { "sk-ant-fake" }
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "x-api-key"), "sk-ant-fake")
        XCTAssertEqual(captured?.url?.absoluteString, "https://api.anthropic.com/v1/models")
    }

    func testAnthropicAPIHTTPErrorIsReported() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, [Data("unauthorized".utf8)])
        }
        let result = await AIProviderTester.test(
            config: config(.anthropicAPI),
            session: MockURLProtocol.makeSession(),
            anthropicKeyProvider: { "sk-ant-bad" }
        )
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.message.contains("401"))
    }

    func testAutoFallsBackToClaudeCLIWhenNoAnthropicKey() async {
        var networkCalled = false
        MockURLProtocol.handler = { request in
            networkCalled = true
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, [])
        }
        let result = await AIProviderTester.test(
            config: config(.auto),
            session: MockURLProtocol.makeSession(),
            anthropicKeyProvider: { nil }
        )
        XCTAssertFalse(networkCalled)
        XCTAssertFalse(result.message.hasPrefix("Automático"))
    }

    func testAutoUsesAnthropicAPIWhenKeyPresent() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, [Data()])
        }
        let result = await AIProviderTester.test(
            config: config(.auto),
            session: MockURLProtocol.makeSession(),
            anthropicKeyProvider: { "sk-ant-fake" }
        )
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.message.contains("Automático"))
    }

    func testOpenAICompatibleMissingBaseURLFailsWithoutNetworkCall() async {
        var networkCalled = false
        MockURLProtocol.handler = { request in
            networkCalled = true
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, [])
        }
        let result = await AIProviderTester.test(
            config: config(.openAICompatible),
            session: MockURLProtocol.makeSession(),
            openAIKeyProvider: { nil }
        )
        XCTAssertFalse(result.ok)
        XCTAssertFalse(networkCalled)
    }

    func testOpenAICompatibleSuccessSendsBearerHeader() async {
        var captured: URLRequest?
        MockURLProtocol.handler = { request in
            captured = request
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, [Data()])
        }
        let result = await AIProviderTester.test(
            config: config(.openAICompatible, baseURL: "https://openrouter.ai/api/v1", model: "x"),
            session: MockURLProtocol.makeSession(),
            openAIKeyProvider: { "or-key" }
        )
        XCTAssertTrue(result.ok)
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer or-key")
        XCTAssertEqual(captured?.url?.absoluteString, "https://openrouter.ai/api/v1/models")
    }

    func testOllamaSuccessListsModels() async {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/tags")
            let body = "{\"models\":[{\"name\":\"llama3\"}]}"
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, [Data(body.utf8)])
        }
        let result = await AIProviderTester.test(
            config: config(.ollama, model: "llama3"),
            session: MockURLProtocol.makeSession()
        )
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.message.contains("llama3"))
    }

    func testOllamaUsesCustomBaseURLWhenProvided() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, [Data("{\"models\":[]}".utf8)])
        }
        let result = await AIProviderTester.test(
            config: config(.ollama, baseURL: "http://192.168.1.50:11434", model: "llama3"),
            session: MockURLProtocol.makeSession()
        )
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.message.contains("192.168.1.50"))
    }

    func testOllamaUnreachableIsReportedAsFailure() async {
        MockURLProtocol.handler = { request in
            throw URLError(.cannotConnectToHost)
        }
        let result = await AIProviderTester.test(
            config: config(.ollama, model: "llama3"),
            session: MockURLProtocol.makeSession()
        )
        XCTAssertFalse(result.ok)
    }
}
