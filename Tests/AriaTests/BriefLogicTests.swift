import XCTest
@testable import aria_capture

final class BriefLogicTests: XCTestCase {

    private func ref(id: Int64, title: String, date: TimeInterval, participants: [String]) -> PastMeetingRef {
        PastMeetingRef(
            record: MeetingRecord(
                id: id,
                date: Date(timeIntervalSince1970: date),
                title: title,
                durationSeconds: 600,
                notePath: "/tmp/nota-\(id).md",
                wavPath: nil
            ),
            participants: participants
        )
    }

    func testParticipantsFromNoteFrontmatter() {
        let note = """
        ---
        titulo: "Sync semanal"
        participantes: ["[[Ana López]]", "[[Juan Pérez]]", "Otros"]
        duracion: "30:00"
        ---

        # Sync
        """
        XCTAssertEqual(MeetingBrief.participants(fromNote: note), ["[[Ana López]]", "[[Juan Pérez]]", "Otros"])
        XCTAssertEqual(MeetingBrief.participants(fromNote: "sin frontmatter"), [])
        XCTAssertEqual(MeetingBrief.participants(fromNote: "participantes: []"), [])
    }

    func testNormalizedStripsWikilinksAndCase() {
        XCTAssertEqual(MeetingBrief.normalized("[[Ana López]]"), "ana lópez")
        XCTAssertEqual(MeetingBrief.normalized("  Juan  "), "juan")
    }

    func testScoreOverlapBeatsTitleBonus() {
        XCTAssertEqual(MeetingBrief.score(participants: ["[[Ana]]"], attendees: ["ana"], pastTitle: "Otra cosa", title: "Sync"), 2)
        XCTAssertEqual(MeetingBrief.score(participants: ["[[Pedro]]"], attendees: ["Ana"], pastTitle: "Sync semanal", title: "Sync semanal"), 1)
        XCTAssertEqual(MeetingBrief.score(participants: ["[[Pedro]]"], attendees: ["Ana"], pastTitle: "Otra", title: "Sync"), 0)
    }

    func testRelevantFiltersRanksAndLimits() {
        let past = [
            ref(id: 1, title: "1:1 Ana", date: 1_000, participants: ["[[Ana]]"]),
            ref(id: 2, title: "Comité", date: 2_000, participants: ["[[Pedro]]"]),
            ref(id: 3, title: "1:1 Ana", date: 3_000, participants: ["[[Ana]]"]),
            ref(id: 4, title: "Sync equipo", date: 4_000, participants: ["[[Ana]]", "[[Juan]]"]),
            ref(id: 5, title: "1:1 Ana", date: 500, participants: ["[[Ana]]"])
        ]
        let selected = MeetingBrief.relevant(past: past, attendees: ["Ana"], title: "1:1 Ana", limit: 3)
        XCTAssertEqual(selected.map(\.record.id), [3, 1, 5])
    }

    func testNextPicksEarliestUpcomingSkippingAllDayAndEnded() {
        let meetings = [
            CalendarMeeting(title: "Terminada", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 900), attendees: [], isAllDay: false),
            CalendarMeeting(title: "Todo el día", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400), attendees: [], isAllDay: true),
            CalendarMeeting(title: "Tarde", start: Date(timeIntervalSince1970: 5_000), end: Date(timeIntervalSince1970: 6_000), attendees: [], isAllDay: false),
            CalendarMeeting(title: "Próxima", start: Date(timeIntervalSince1970: 2_000), end: Date(timeIntervalSince1970: 3_000), attendees: ["Ana"], isAllDay: false)
        ]
        XCTAssertEqual(CalendarMeeting.next(among: meetings, at: Date(timeIntervalSince1970: 1_000))?.title, "Próxima")
        XCTAssertNil(CalendarMeeting.next(among: [], at: Date(timeIntervalSince1970: 0)))
    }
}
