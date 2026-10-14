import XCTest
@testable import aria_capture

final class SearchTests: XCTestCase {

    private var tempDir: URL!
    private var store: MeetingStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFtsQueryQuotedPrefixTokens() {
        XCTAssertEqual(MeetingSearch.ftsQuery(from: "¿qué prometí?"), "\"qué\"* \"prometí\"*")
        XCTAssertEqual(MeetingSearch.ftsQuery(from: "regresión"), "\"regresión\"*")
        XCTAssertEqual(MeetingSearch.ftsQuery(from: "  ...  "), "")
    }

    func testSearchFindsTranscriptNotesAndTitleAccentInsensitive() throws {
        try store.saveMeeting(
            date: Date(timeIntervalSince1970: 1_754_000_000),
            title: "Sync piloto Acme",
            durationSeconds: 900,
            notePath: "/tmp/n1.md",
            wavPath: nil,
            segments: [
                TranscriptSegment(start: 0, end: 5, text: "Falta la regresión del release.", speaker: "Otros"),
                TranscriptSegment(start: 5, end: 9, text: "Yo la corro mañana.", speaker: "Yo")
            ],
            quickNotes: [QuickNote(timestamp: "10:00", text: "pedir accesos al ambiente")]
        )
        try store.saveMeeting(
            date: Date(timeIntervalSince1970: 1_754_100_000),
            title: "Comité mensual",
            durationSeconds: 600,
            notePath: "/tmp/n2.md",
            wavPath: nil,
            segments: [TranscriptSegment(start: 0, end: 4, text: "Presupuesto aprobado.", speaker: "Otros")],
            quickNotes: []
        )

        let byTranscript = try MeetingSearch.search("regresion", store: store)
        XCTAssertEqual(byTranscript.count, 1)
        XCTAssertEqual(byTranscript[0].title, "Sync piloto Acme")
        XCTAssertEqual(byTranscript[0].kind, "transcript")
        XCTAssertEqual(byTranscript[0].speaker, "Otros")
        XCTAssertTrue(byTranscript[0].snippet.contains("«regresión»"))

        let byNote = try MeetingSearch.search("accesos ambiente", store: store)
        XCTAssertEqual(byNote.count, 1)
        XCTAssertEqual(byNote[0].kind, "nota")

        let byTitle = try MeetingSearch.search("comité", store: store)
        XCTAssertTrue(byTitle.contains { $0.kind == "título" && $0.title == "Comité mensual" })

        XCTAssertEqual(try MeetingSearch.search("inexistente", store: store).count, 0)
    }

    func testSearchRejectsEmptyQuery() {
        XCTAssertThrowsError(try MeetingSearch.search("  ¿? ", store: store))
    }

    func testLineFormat() {
        let hit = SearchHit(
            meetingID: 7,
            title: "Sync",
            date: Date(timeIntervalSince1970: 1_754_000_000),
            kind: "transcript",
            speaker: "Yo",
            snippet: "«regresión» mañana"
        )
        let line = MeetingSearch.line(for: hit)
        XCTAssertTrue(line.hasPrefix("[7] "))
        XCTAssertTrue(line.contains("Sync — (transcript · Yo) «regresión» mañana"))
    }
}
