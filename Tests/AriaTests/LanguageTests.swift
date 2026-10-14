import XCTest
@testable import aria_capture

final class LanguageTests: XCTestCase {

    func testConfigValidatesLanguage() throws {
        var config = AriaConfig()
        XCTAssertEqual(config.language, "es")
        try config.set(key: "language", value: "AUTO")
        XCTAssertEqual(config.language, "auto")
        try config.set(key: "language", value: "en")
        XCTAssertEqual(config.language, "en")
        XCTAssertThrowsError(try config.set(key: "language", value: "fr"))
    }

    func testLanguageInstructionPerMode() {
        XCTAssertNil(MeetingEnhancer.languageInstruction("es"))
        XCTAssertTrue(MeetingEnhancer.languageInstruction("en")!.contains("inglés"))
        XCTAssertTrue(MeetingEnhancer.languageInstruction("auto")!.contains("idioma predominante"))
    }

    func testComposedSystemPromptOrdersLanguageThenTemplate() {
        let base = MeetingEnhancer.systemPrompt
        let composed = MeetingEnhancer.composedSystemPrompt(
            base: base,
            language: "auto",
            template: Recipe(name: "ventas", prompt: "Prioriza objeciones.")
        )
        XCTAssertTrue(composed.hasPrefix(base))
        let languageIndex = composed.range(of: "idioma predominante")!.lowerBound
        let templateIndex = composed.range(of: "## Plantilla \"ventas\"")!.lowerBound
        XCTAssertLessThan(languageIndex, templateIndex)

        XCTAssertEqual(MeetingEnhancer.composedSystemPrompt(base: base, language: "es", template: nil), base)
    }
}

extension LanguageTests {

    func testDisplayValueReturnsStoredNormalized() throws {
        var config = AriaConfig()
        try config.set(key: "language", value: "ES")
        XCTAssertEqual(config.displayValue(forKey: "language"), "es")
        try config.set(key: "calendarIgnore", value: "(ninguno)")
        XCTAssertEqual(config.displayValue(forKey: "calendarIgnore"), "(ninguno)")
        XCTAssertNil(config.displayValue(forKey: "inexistente"))
    }
}
