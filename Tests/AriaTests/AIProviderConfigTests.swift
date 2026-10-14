import XCTest
@testable import aria_capture

final class AIProviderConfigTests: XCTestCase {

    func testDefaultProviderIsAutoWithEmptyModelAndBaseURL() {
        let config = AriaConfig()
        XCTAssertEqual(config.aiProvider, .auto)
        XCTAssertEqual(config.aiModel, "")
        XCTAssertEqual(config.aiBaseURL, "")
    }

    func testSetAndDisplayAiProvider() throws {
        var config = AriaConfig()
        try config.set(key: "aiProvider", value: "ollama")
        XCTAssertEqual(config.aiProvider, .ollama)
        XCTAssertEqual(config.displayValue(forKey: "aiProvider"), "ollama")
    }

    func testSetAiProviderRejectsUnknownValue() {
        var config = AriaConfig()
        XCTAssertThrowsError(try config.set(key: "aiProvider", value: "bogus"))
    }

    func testSetAiModelAndAiBaseURL() throws {
        var config = AriaConfig()
        try config.set(key: "aiModel", value: "gpt-4o-mini")
        try config.set(key: "aiBaseURL", value: "https://api.openai.com/v1")
        XCTAssertEqual(config.displayValue(forKey: "aiModel"), "gpt-4o-mini")
        XCTAssertEqual(config.displayValue(forKey: "aiBaseURL"), "https://api.openai.com/v1")
    }

    func testDisplayValueShowsPlaceholderWhenEmpty() {
        let config = AriaConfig()
        XCTAssertEqual(config.displayValue(forKey: "aiModel"), "(ninguno)")
        XCTAssertEqual(config.displayValue(forKey: "aiBaseURL"), "(ninguno)")
    }

    func testListingIncludesAiProviderKeys() {
        XCTAssertTrue(AriaConfig().listing.contains("aiProvider"))
    }

    func testAllProviderKindsHaveLabelAndPrivacyNote() {
        for kind in AIProviderKind.allCases {
            XCTAssertFalse(kind.label.isEmpty)
            XCTAssertFalse(kind.privacyNote.isEmpty)
        }
        XCTAssertTrue(AIProviderKind.ollama.isLocal)
        XCTAssertFalse(AIProviderKind.claudeCLI.isLocal)
        XCTAssertFalse(AIProviderKind.anthropicAPI.isLocal)
        XCTAssertFalse(AIProviderKind.openAICompatible.isLocal)
        XCTAssertFalse(AIProviderKind.auto.isLocal)
    }

    func testFactoryReturnsNilForOpenAICompatibleWithoutBaseURLOrModel() {
        var config = AriaConfig()
        config.aiProvider = .openAICompatible
        config.aiBaseURL = ""
        config.aiModel = ""
        XCTAssertNil(AIProviderFactory.makeBackend(config: config))
    }

    func testFactoryBuildsOpenAICompatibleBackendWithGivenConfig() {
        var config = AriaConfig()
        config.aiProvider = .openAICompatible
        config.aiBaseURL = "https://api.groq.com/openai/v1"
        config.aiModel = "llama-3.1-70b-versatile"
        let backend = AIProviderFactory.makeBackend(config: config)
        XCTAssertTrue(backend?.backendName.contains("llama-3.1-70b-versatile") ?? false)
        XCTAssertTrue(backend?.backendName.contains("https://api.groq.com/openai/v1") ?? false)
    }

    func testFactoryReturnsNilForOllamaWithoutModel() {
        var config = AriaConfig()
        config.aiProvider = .ollama
        config.aiModel = ""
        XCTAssertNil(AIProviderFactory.makeBackend(config: config))
    }

    func testFactoryBuildsOllamaBackendWithDefaultBaseURLWhenEmpty() {
        var config = AriaConfig()
        config.aiProvider = .ollama
        config.aiModel = "llama3"
        config.aiBaseURL = ""
        let backend = AIProviderFactory.makeBackend(config: config)
        XCTAssertTrue(backend?.backendName.contains("llama3") ?? false)
        XCTAssertTrue((backend as? OllamaClient)?.baseURL == OllamaClient.defaultBaseURL)
    }

    func testFactoryClaudeCLIProviderReturnsCLIBackendTypeWhenPresent() {
        var config = AriaConfig()
        config.aiProvider = .claudeCLI
        if let backend = AIProviderFactory.makeBackend(config: config) {
            XCTAssertTrue(backend is ClaudeCLIClient)
        }
    }
}
