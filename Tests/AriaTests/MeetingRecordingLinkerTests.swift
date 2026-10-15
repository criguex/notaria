import XCTest
@testable import aria_capture

final class MeetingRecordingLinkerTests: XCTestCase {

    private func meeting(
        _ title: String,
        start: TimeInterval,
        end: TimeInterval,
        eventIdentifier: String? = nil
    ) -> CalendarMeeting {
        CalendarMeeting(
            title: title,
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            attendees: [],
            isAllDay: false,
            eventIdentifier: eventIdentifier
        )
    }

    private func record(
        _ id: Int64,
        _ title: String,
        start: TimeInterval,
        durationSeconds: Double,
        externalID: String? = nil
    ) -> MeetingRecord {
        MeetingRecord(
            id: id,
            date: Date(timeIntervalSince1970: start),
            title: title,
            durationSeconds: durationSeconds,
            notePath: "/tmp/\(id).md",
            wavPath: nil,
            externalID: externalID
        )
    }

    func testMatchByExactEventIdentifierIgnoresTimeAndTitle() {
        let meeting = meeting("Sync semanal", start: 100_000, end: 100_900, eventIdentifier: "evt-1")
        let records = [
            record(1, "Reunión sin relación", start: 0, durationSeconds: 60, externalID: "evt-1"),
            record(2, "Sync semanal", start: 100_000, durationSeconds: 900)
        ]
        XCTAssertEqual(MeetingRecordingLinker.match(meeting: meeting, in: records)?.id, 1)
    }

    func testMatchBySingleOverlappingCandidateWithoutEventIdentifier() {
        let meeting = meeting("Reunión con cliente", start: 100_000, end: 103_600)
        let records = [
            record(5, "Titulo distinto en la nota", start: 100_050, durationSeconds: 3_500)
        ]
        XCTAssertEqual(MeetingRecordingLinker.match(meeting: meeting, in: records)?.id, 5)
    }

    func testMatchPicksHighestTitleSimilarityAmongMultipleOverlappingCandidates() {
        let meeting = meeting("Revisión de presupuesto Q3", start: 100_000, end: 103_600)
        let records = [
            record(1, "Charla random sin relacion", start: 100_100, durationSeconds: 3_000),
            record(2, "Revisión de presupuesto Q3", start: 100_200, durationSeconds: 3_200)
        ]
        XCTAssertEqual(MeetingRecordingLinker.match(meeting: meeting, in: records)?.id, 2)
    }

    func testNoMatchWhenNoOverlapAndNoEventIdentifier() {
        let meeting = meeting("Reunión aislada", start: 100_000, end: 103_600)
        let records = [
            record(1, "Reunión aislada", start: 500_000, durationSeconds: 600)
        ]
        XCTAssertNil(MeetingRecordingLinker.match(meeting: meeting, in: records))
    }

    func testNoMatchWhenMultipleCandidatesHaveLowTitleSimilarity() {
        let meeting = meeting("Sesion de planificacion", start: 100_000, end: 103_600)
        let records = [
            record(1, "Charla totalmente distinta", start: 100_100, durationSeconds: 3_000),
            record(2, "Otro tema sin relacion alguna", start: 100_200, durationSeconds: 3_200)
        ]
        XCTAssertNil(MeetingRecordingLinker.match(meeting: meeting, in: records))
    }

    func testOverlapMarginAllowsRecordingThatStartedSlightlyBeforeEvent() {
        let meeting = meeting("Demo", start: 100_000, end: 103_600)
        let withinMargin = record(1, "Demo", start: 100_000 - MeetingRecordingLinker.overlapMarginSeconds + 1, durationSeconds: 60)
        let outsideMargin = record(2, "Demo", start: 100_000 - MeetingRecordingLinker.overlapMarginSeconds - 60, durationSeconds: 1)
        XCTAssertEqual(MeetingRecordingLinker.match(meeting: meeting, in: [withinMargin])?.id, 1)
        XCTAssertNil(MeetingRecordingLinker.match(meeting: meeting, in: [outsideMargin]))
    }

    func testTitleSimilarityIsCaseAndDiacriticInsensitive() {
        let similarity = MeetingRecordingLinker.titleSimilarity("Revisión de Presupuesto", "revision de presupuesto")
        XCTAssertEqual(similarity, 1.0, accuracy: 0.0001)
    }
}
