import XCTest
@testable import aria_capture

final class RecipeTests: XCTestCase {

    private var scratch: URL!
    private var store: RecipeStore!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-recipes-\(UUID().uuidString)", isDirectory: true)
        store = RecipeStore(directory: scratch)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testEnsureDefaultsSeedsOnceWithoutOverwriting() throws {
        let created = try store.ensureDefaults()
        XCTAssertEqual(created.sorted(), ["action-items", "follow-up-email", "resumen-ejecutivo"])

        let customURL = scratch.appendingPathComponent("follow-up-email.md")
        try "mi versión editada".write(to: customURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(try store.ensureDefaults(), [])
        XCTAssertEqual(try String(contentsOf: customURL, encoding: .utf8), "mi versión editada")
    }

    func testListReadsMarkdownSortedAndIgnoresEmptyAndForeign() throws {
        try store.ensureDefaults()
        try "".write(to: scratch.appendingPathComponent("vacia.md"), atomically: true, encoding: .utf8)
        try "no soy recipe".write(to: scratch.appendingPathComponent("notas.txt"), atomically: true, encoding: .utf8)

        let names = store.list().map(\.name)
        XCTAssertEqual(names, ["action-items", "follow-up-email", "resumen-ejecutivo"])
    }

    func testRecipeLookupIsCaseInsensitive() throws {
        try store.ensureDefaults()
        XCTAssertEqual(store.recipe(named: "Follow-Up-Email")?.name, "follow-up-email")
        XCTAssertNil(store.recipe(named: "inexistente"))
    }

    func testListOnMissingDirectoryIsEmpty() {
        XCTAssertEqual(store.list(), [])
    }

    func testRecipeMessageContainsContextAndPrompt() {
        let recipe = Recipe(name: "follow-up-email", prompt: "Redacta el correo.")
        let message = MeetingChat.recipeMessage(recipe: recipe, context: "### Reunión X")
        XCTAssertTrue(message.contains("## Contexto de reuniones"))
        XCTAssertTrue(message.contains("### Reunión X"))
        XCTAssertTrue(message.contains("## Recipe: follow-up-email"))
        XCTAssertTrue(message.contains("Redacta el correo."))
    }
}
