import XCTest
@testable import aria_capture

final class GranolaImportTests: XCTestCase {

    private var tempDir: URL!
    private var jsonDir: URL!
    private var notesDir: URL!
    private var store: MeetingStore!
    private var writer: ObsidianWriter!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-granola-tests-\(UUID().uuidString)", isDirectory: true)
        jsonDir = tempDir.appendingPathComponent("export", isDirectory: true)
        notesDir = tempDir.appendingPathComponent("Reuniones", isDirectory: true)
        try FileManager.default.createDirectory(at: jsonDir, withIntermediateDirectories: true)
        store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        writer = ObsidianWriter(directory: notesDir)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeFixture(id: String, title: String, meetingAt: String, summary: String, transcript: String? = nil) throws {
        let record = """
        {
          "source": "granola",
          "id": "\(id)",
          "title": "\(title)",
          "meeting_at": "\(meetingAt)",
          "created_at": "\(meetingAt)",
          "updated_at": "\(meetingAt)",
          "url": "https://notes.granola.ai/d/\(id)",
          "participants": ["persona ficticia uno <ficticia1@example.com>", "persona ficticia dos <ficticia2@example.com>"],
          "summary_markdown": "\(summary)",
          "transcript": \(transcript.map { "\"\($0)\"" } ?? "null"),
          "transcript_unavailable": \(transcript == nil ? "true" : "false")
        }
        """
        try record.write(to: jsonDir.appendingPathComponent("\(id).json"), atomically: true, encoding: .utf8)
    }

    func testImportCreatesNoteWithGranolaFrontmatterAndIndexesSummary() throws {
        try writeFixture(
            id: "aaaaaaaa-0000-0000-0000-000000000001",
            title: "Reunión ficticia de prueba",
            meetingAt: "2026-01-15T10:00:00.000-05:00",
            summary: "# Resumen ficticio\\n\\n- Punto de prueba sobre presupuesto inventado"
        )

        let result = try GranolaImporter.importDirectory(jsonDir, writer: writer, store: store)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.updated, 0)
        XCTAssertTrue(result.failed.isEmpty)

        let records = try store.recentMeetings()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].source, "granola")
        XCTAssertEqual(records[0].externalID, "granola:aaaaaaaa-0000-0000-0000-000000000001")

        let content = try String(contentsOfFile: records[0].notePath, encoding: .utf8)
        XCTAssertTrue(content.contains("fuente: granola"))
        XCTAssertTrue(content.contains("granola_id: \"aaaaaaaa-0000-0000-0000-000000000001\""))
        XCTAssertTrue(content.contains("tags: [reunion, granola]"))
        XCTAssertTrue(content.contains("Resumen ficticio"))

        let hits = try MeetingSearch.search("presupuesto inventado", store: store)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].title, "Reunión ficticia de prueba")
    }

    func testReimportIsIdempotentAndUpdatesInPlace() throws {
        try writeFixture(
            id: "aaaaaaaa-0000-0000-0000-000000000002",
            title: "Reunión ficticia repetible",
            meetingAt: "2026-02-20T09:00:00.000-05:00",
            summary: "Primera version del resumen ficticio"
        )

        let first = try GranolaImporter.importDirectory(jsonDir, writer: writer, store: store)
        XCTAssertEqual(first.imported, 1)
        let firstRecords = try store.recentMeetings()
        XCTAssertEqual(firstRecords.count, 1)
        let notePath = firstRecords[0].notePath

        try writeFixture(
            id: "aaaaaaaa-0000-0000-0000-000000000002",
            title: "Reunión ficticia repetible",
            meetingAt: "2026-02-20T09:00:00.000-05:00",
            summary: "Segunda version del resumen ficticio actualizado"
        )

        let second = try GranolaImporter.importDirectory(jsonDir, writer: writer, store: store)
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.updated, 1)

        let secondRecords = try store.recentMeetings()
        XCTAssertEqual(secondRecords.count, 1, "no debe duplicar la reunión al re-importar")
        XCTAssertEqual(secondRecords[0].notePath, notePath, "debe sobreescribir el mismo archivo")

        let content = try String(contentsOfFile: notePath, encoding: .utf8)
        XCTAssertTrue(content.contains("Segunda version"))
        XCTAssertFalse(content.contains("Primera version"))

        let allFiles = try FileManager.default.contentsOfDirectory(atPath: notesDir.path)
        XCTAssertEqual(allFiles.count, 1, "no debe quedar un segundo .md por colisión de nombre")
    }

    func testImportWithTranscriptIndexesSegments() throws {
        try writeFixture(
            id: "aaaaaaaa-0000-0000-0000-000000000003",
            title: "Reunión ficticia con transcript",
            meetingAt: "2026-03-01T08:00:00.000-05:00",
            summary: "Resumen con transcript ficticio",
            transcript: "Hola equipo ficticio\\nVamos a revisar el tema inventado"
        )

        let result = try GranolaImporter.importDirectory(jsonDir, writer: writer, store: store)
        XCTAssertEqual(result.imported, 1)

        let hits = try MeetingSearch.search("inventado", store: store)
        XCTAssertTrue(hits.contains { $0.kind == "transcript" })
    }

    func testInvalidRecordGoesToFailedWithoutCrashing() throws {
        try "{ \"not\": \"a granola record\" }".write(
            to: jsonDir.appendingPathComponent("bad.json"), atomically: true, encoding: .utf8
        )
        try writeFixture(
            id: "aaaaaaaa-0000-0000-0000-000000000004",
            title: "Reunión ficticia válida junto a una inválida",
            meetingAt: "2026-04-01T08:00:00.000-05:00",
            summary: "Resumen válido ficticio"
        )

        let result = try GranolaImporter.importDirectory(jsonDir, writer: writer, store: store)
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.failed.count, 1)
        XCTAssertEqual(result.failed.first?.file, "bad.json")
    }

    func testImportDirectoryRejectsNonDirectoryPath() throws {
        let filePath = tempDir.appendingPathComponent("not-a-dir.txt")
        try "x".write(to: filePath, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try GranolaImporter.importDirectory(filePath, writer: writer, store: store))
    }
}
