import XCTest
@testable import aria_capture

final class NotepadTests: XCTestCase {

    private var fileURL: URL!
    private var store: NotesStore!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-notes-\(UUID().uuidString).md")
        store = NotesStore(fileURL: fileURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testAppendAllClearCycle() throws {
        try store.append("primera nota", date: Date(timeIntervalSince1970: 1_754_000_000))
        try store.append("línea uno\nlínea dos", date: Date(timeIntervalSince1970: 1_754_000_060))

        let notes = store.all()
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].text, "primera nota")
        XCTAssertEqual(notes[1].text, "línea uno · línea dos")
        XCTAssertFalse(notes[0].timestamp.isEmpty)

        try store.clear()
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        try store.clear()
    }

    func testDefaultPathIsStableUnderDocumentsAria() {
        let defaultStore = NotesStore()
        XCTAssertTrue(defaultStore.fileURL.path.hasSuffix("Documents/Aria/notes.md"))
    }
}
