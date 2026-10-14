import XCTest
@testable import aria_capture

final class TemplateTests: XCTestCase {

    private var scratch: URL!
    private var store: TemplateStore!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-templates-\(UUID().uuidString)", isDirectory: true)
        store = TemplateStore(directory: scratch)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testEnsureDefaultsSeedsOnceWithoutOverwriting() throws {
        XCTAssertEqual(try store.ensureDefaults().sorted(), ["1-1", "standup", "ventas"])
        let custom = scratch.appendingPathComponent("ventas.md")
        try "mi enfoque de ventas".write(to: custom, atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.ensureDefaults(), [])
        XCTAssertEqual(try String(contentsOf: custom, encoding: .utf8), "mi enfoque de ventas")
    }

    func testLookupCaseInsensitive() throws {
        try store.ensureDefaults()
        XCTAssertEqual(store.template(named: "Standup")?.name, "standup")
        XCTAssertNil(store.template(named: "retro"))
    }

    func testComposedSystemPromptAppendsTemplateOrReturnsBase() {
        let base = MeetingEnhancer.systemPrompt
        XCTAssertEqual(MeetingEnhancer.composedSystemPrompt(base: base, template: nil), base)

        let composed = MeetingEnhancer.composedSystemPrompt(
            base: base,
            template: Recipe(name: "ventas", prompt: "Prioriza objeciones.")
        )
        XCTAssertTrue(composed.hasPrefix(base))
        XCTAssertTrue(composed.contains("## Plantilla \"ventas\" — enfoque de esta reunión"))
        XCTAssertTrue(composed.contains("Prioriza objeciones."))
        XCTAssertTrue(composed.contains("NUNCA inventes nombres"))
    }
}
