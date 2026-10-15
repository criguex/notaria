import XCTest
@testable import aria_capture

final class SpeakerProfileStorageTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-speaker-profiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() throws -> MeetingStore {
        try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
    }

    private func makeMeeting(_ store: MeetingStore) throws -> Int64 {
        try store.saveMeeting(
            date: Date(), title: "Reunión", durationSeconds: 60,
            notePath: "/tmp/nota.md", wavPath: nil,
            segments: [TranscriptSegment(start: 0, end: 1, text: "hola", speaker: "Hablante 1")],
            quickNotes: []
        )
    }

    func testSaveAndFetchSpeakerEmbeddings() throws {
        let store = try makeStore()
        let meetingID = try makeMeeting(store)
        try store.saveSpeakerEmbeddings(["Hablante 1": SpeakerEmbedding(vector: [1, 0, 0])], meetingID: meetingID)

        let fetched = try store.speakerEmbeddings(meetingID: meetingID)
        XCTAssertEqual(fetched["Hablante 1"]?.vector, [1, 0, 0])
    }

    func testSaveSpeakerEmbeddingsNoOpOnEmptyDictionary() throws {
        let store = try makeStore()
        let meetingID = try makeMeeting(store)
        try store.saveSpeakerEmbeddings([:], meetingID: meetingID)
        XCTAssertTrue(try store.speakerEmbeddings(meetingID: meetingID).isEmpty)
    }

    func testEmbeddingsAreEncryptedAtRest() throws {
        let fileURL = tempDir.appendingPathComponent("test.db")
        let store = try MeetingStore(databaseURL: fileURL)
        let meetingID = try makeMeeting(store)
        try store.saveSpeakerEmbeddings(["Hablante 1": SpeakerEmbedding(vector: [0.123456, 0, 0])], meetingID: meetingID)

        let raw = try Data(contentsOf: fileURL)
        let rawString = String(decoding: raw, as: UTF8.self)
        XCTAssertFalse(rawString.contains("0.123456"))
    }

    func testRenameSpeakerProfileUpdatesLabel() throws {
        let store = try makeStore()
        let meetingID = try makeMeeting(store)
        try store.saveSpeakerEmbeddings(["Hablante 1": SpeakerEmbedding(vector: [1, 0, 0])], meetingID: meetingID)

        try store.renameSpeakerProfile(meetingID: meetingID, oldLabel: "Hablante 1", newLabel: "Ana")
        let fetched = try store.speakerEmbeddings(meetingID: meetingID)
        XCTAssertNil(fetched["Hablante 1"])
        XCTAssertEqual(fetched["Ana"]?.vector, [1, 0, 0])
    }

    func testSpeakerEmbeddingsScopedPerMeeting() throws {
        let store = try makeStore()
        let meetingA = try makeMeeting(store)
        let meetingB = try makeMeeting(store)
        try store.saveSpeakerEmbeddings(["Hablante 1": SpeakerEmbedding(vector: [1, 0, 0])], meetingID: meetingA)

        XCTAssertFalse(try store.speakerEmbeddings(meetingID: meetingA).isEmpty)
        XCTAssertTrue(try store.speakerEmbeddings(meetingID: meetingB).isEmpty)
    }
}
