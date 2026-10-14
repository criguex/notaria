import XCTest
@testable import aria_capture

final class TranscriptEditingTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-edit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRenameSpeakerUpdatesAllSegments() throws {
        let store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "Hola", speaker: "Yo"),
            TranscriptSegment(start: 5, end: 10, text: "Qué tal", speaker: "Otros"),
            TranscriptSegment(start: 10, end: 15, text: "Bien", speaker: "Yo"),
            TranscriptSegment(start: 15, end: 20, text: "Vamos", speaker: "Otros")
        ]
        let meetingID = try store.saveMeeting(
            date: Date(), title: "Test", durationSeconds: 20,
            notePath: "/tmp/test.md", wavPath: nil, segments: segments, quickNotes: []
        )

        try store.renameSpeaker(meetingID: meetingID, oldSpeaker: "Otros", newSpeaker: "Juan")

        let updated = try store.segments(meetingID: meetingID)
        XCTAssertEqual(updated[1].speaker, "Juan")
        XCTAssertEqual(updated[3].speaker, "Juan")
        XCTAssertEqual(updated[0].speaker, "Yo")
        XCTAssertEqual(updated[2].speaker, "Yo")
    }

    func testUpdateSegmentTextPersists() throws {
        let store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "Hola equipo", speaker: "Yo"),
            TranscriptSegment(start: 5, end: 10, text: "Qué tal", speaker: "Otros")
        ]
        let meetingID = try store.saveMeeting(
            date: Date(), title: "Test", durationSeconds: 10,
            notePath: "/tmp/test.md", wavPath: nil, segments: segments, quickNotes: []
        )

        try store.updateSegmentText(meetingID: meetingID, segmentIndex: 0, newText: "Hola a todos")

        let updated = try store.segments(meetingID: meetingID)
        XCTAssertEqual(updated[0].text, "Hola a todos")
        XCTAssertEqual(updated[1].text, "Qué tal")
    }

    func testUpdateSegmentTextInvalidIndex() throws {
        let store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "Hola", speaker: "Yo")
        ]
        let meetingID = try store.saveMeeting(
            date: Date(), title: "Test", durationSeconds: 5,
            notePath: "/tmp/test.md", wavPath: nil, segments: segments, quickNotes: []
        )

        XCTAssertThrowsError(try store.updateSegmentText(meetingID: meetingID, segmentIndex: 5, newText: "Nuevo"))
    }

    func testAgendaDayGrouping() throws {
        let calendar = Calendar.current
        let today = Date()
        let startOfDay = calendar.startOfDay(for: today)

        let meetings = [
            CalendarMeeting(title: "Standup", start: startOfDay.addingTimeInterval(3600), end: startOfDay.addingTimeInterval(5400), attendees: ["Ana"], isAllDay: false),
            CalendarMeeting(title: "Sync", start: startOfDay.addingTimeInterval(10800), end: startOfDay.addingTimeInterval(12600), attendees: ["Juan"], isAllDay: false),
            CalendarMeeting(title: "1:1 con Marta", start: startOfDay.addingTimeInterval(18000), end: startOfDay.addingTimeInterval(19800), attendees: ["Marta"], isAllDay: false)
        ]

        let sorted = meetings.sorted { $0.start < $1.start }
        XCTAssertEqual(sorted.count, 3)
        XCTAssertEqual(sorted[0].title, "Standup")
        XCTAssertEqual(sorted[2].title, "1:1 con Marta")
        XCTAssertTrue(sorted[0].start < sorted[1].start)
        XCTAssertTrue(sorted[1].start < sorted[2].start)
    }

    func testMultipleSegmentEdits() throws {
        let store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "Primero", speaker: "Yo"),
            TranscriptSegment(start: 5, end: 10, text: "Segundo", speaker: "Otros"),
            TranscriptSegment(start: 10, end: 15, text: "Tercero", speaker: "Yo")
        ]
        let meetingID = try store.saveMeeting(
            date: Date(), title: "Test", durationSeconds: 15,
            notePath: "/tmp/test.md", wavPath: nil, segments: segments, quickNotes: []
        )

        try store.updateSegmentText(meetingID: meetingID, segmentIndex: 0, newText: "Primero editado")
        try store.updateSegmentText(meetingID: meetingID, segmentIndex: 2, newText: "Tercero editado")
        try store.renameSpeaker(meetingID: meetingID, oldSpeaker: "Otros", newSpeaker: "María")

        let updated = try store.segments(meetingID: meetingID)
        XCTAssertEqual(updated[0].text, "Primero editado")
        XCTAssertEqual(updated[1].speaker, "María")
        XCTAssertEqual(updated[2].text, "Tercero editado")
    }
}
