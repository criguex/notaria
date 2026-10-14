import XCTest
@testable import aria_capture

final class StorageTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCipherRoundtripAndLegacyPassthrough() throws {
        let cipher = try CacheCipher()
        let secret = "Transcript confidencial: cerramos el sprint el viernes"
        let stored = cipher.encrypt(secret)
        XCTAssertTrue(stored.hasPrefix("enc1:"))
        XCTAssertFalse(stored.contains("sprint"))
        XCTAssertEqual(cipher.decrypt(stored), secret)
        XCTAssertEqual(cipher.decrypt("fila legacy en claro"), "fila legacy en claro")
    }

    func testMeetingStoreSaveRecentAndPurge() throws {
        let store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let segments = [TranscriptSegment(start: 0, end: 5, text: "Hola equipo", speaker: "Yo")]
        let notes = [QuickNote(timestamp: "10:00", text: "revisar presupuesto")]

        try store.saveMeeting(
            date: Date(), title: "Reunión reciente", durationSeconds: 300,
            notePath: "/tmp/reciente.md", wavPath: nil, segments: segments, quickNotes: notes
        )
        try store.saveMeeting(
            date: Date(timeIntervalSinceNow: -40 * 86_400), title: "Reunión vieja",
            durationSeconds: 60, notePath: "/tmp/vieja.md", wavPath: nil,
            segments: [], quickNotes: []
        )

        XCTAssertEqual(try store.recentMeetings().count, 2)
        XCTAssertEqual(try store.recentMeetings()[0].title, "Reunión reciente")

        try store.purge(olderThanDays: 30)
        let remaining = try store.recentMeetings()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].title, "Reunión reciente")

        XCTAssertEqual(try store.purge(olderThanDays: 0), 0)
    }

    func testObsidianWriterFrontmatterAndCollision() throws {
        let writer = ObsidianWriter(directory: tempDir.appendingPathComponent("Reuniones", isDirectory: true))
        let note = MeetingNote(
            title: "Sync: cierre / QA",
            date: Date(),
            participants: ["[[Ana]]", "Otros"],
            durationSeconds: 125,
            body: "# Sync\n\nCuerpo.",
            transcript: "[00:00] Yo: hola"
        )
        let first = try writer.write(note)
        let second = try writer.write(note)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.lastPathComponent.contains("(2)"))

        let content = try String(contentsOf: first, encoding: .utf8)
        XCTAssertTrue(content.contains("titulo: \"Sync: cierre / QA\""))
        XCTAssertTrue(content.contains("participantes: [\"[[Ana]]\", \"Otros\"]"))
        XCTAssertTrue(content.contains("duracion: 02:05"))
        XCTAssertTrue(content.contains("> [!note]- Transcript"))
    }

    func testYamlQuotingAndSanitizing() {
        XCTAssertEqual(ObsidianWriter.yamlQuoted("a \"b\""), "\"a \\\"b\\\"\"")
        XCTAssertEqual(ObsidianWriter.sanitized("Reunión: plan / Q3?"), "Reunión plan  Q3")
        XCTAssertEqual(ObsidianWriter.sanitized("///"), "Reunion sin titulo")
    }

    func testNotesStoreAppendAndParse() throws {
        let store = NotesStore(fileURL: tempDir.appendingPathComponent("notes.md"))
        try store.append("primera nota", date: Date(timeIntervalSince1970: 0))
        try store.append("segunda nota")
        let all = store.all()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].text, "primera nota")
        XCTAssertFalse(all[1].timestamp.isEmpty)
    }

    func testConfigValidation() throws {
        var config = AriaConfig()
        XCTAssertThrowsError(try config.set(key: "whisperModel", value: "gigante"))
        XCTAssertThrowsError(try config.set(key: "keepAudio", value: "quizás"))
        XCTAssertThrowsError(try config.set(key: "retentionDays", value: "-1"))
        XCTAssertThrowsError(try config.set(key: "claveInventada", value: "x"))
        try config.set(key: "whisperModel", value: "medium")
        try config.set(key: "retentionDays", value: "15")
        try config.set(key: "alwaysOn", value: "true")
        XCTAssertEqual(config.whisperModel, "medium")
        XCTAssertEqual(config.retentionDays, 15)
        XCTAssertTrue(config.alwaysOn)
    }

    func testGrowableRecorderTimestampPlacementAndWav() throws {
        let recorder = GrowableStereoRecorder(maxSeconds: 10)
        recorder.begin(epochSeconds: 100)

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for index in 0..<16_000 {
            buffer.floatChannelData![0][index] = 0.5
        }

        recorder.addMic(buffer, atHostSeconds: 100)
        recorder.addSystem(buffer, atHostSeconds: 102)

        XCTAssertEqual(recorder.recordedSeconds, 3, accuracy: 0.1)
        XCTAssertNotNil(recorder.secondsSinceSystemAudio)

        let wavURL = tempDir.appendingPathComponent("out.wav")
        let result = try recorder.write(to: wavURL)
        XCTAssertEqual(result.seconds, 3, accuracy: 0.1)
        XCTAssertGreaterThan(result.micPeak, 0.4)
        XCTAssertGreaterThan(result.systemPeak, 0.4)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wavURL.path))
    }
}

import AVFoundation
