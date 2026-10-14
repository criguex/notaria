import XCTest
@testable import aria_capture

final class CalendarLogicTests: XCTestCase {

    private func meeting(
        _ title: String,
        start: TimeInterval,
        end: TimeInterval,
        attendees: [String] = [],
        allDay: Bool = false
    ) -> CalendarMeeting {
        CalendarMeeting(
            title: title,
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            attendees: attendees,
            isAllDay: allDay
        )
    }

    func testCurrentPicksOngoingMeeting() {
        let meetings = [
            meeting("Pasada", start: 0, end: 1_000),
            meeting("Ahora", start: 1_500, end: 3_000),
            meeting("Futura", start: 10_000, end: 12_000)
        ]
        XCTAssertEqual(CalendarMeeting.current(among: meetings, at: Date(timeIntervalSince1970: 2_000))?.title, "Ahora")
    }

    func testCurrentIncludesMeetingStartingWithinTolerance() {
        let meetings = [meeting("Por empezar", start: 2_000, end: 3_000)]
        XCTAssertEqual(
            CalendarMeeting.current(among: meetings, at: Date(timeIntervalSince1970: 2_000 - CalendarMeeting.joinToleranceSeconds))?.title,
            "Por empezar"
        )
        XCTAssertNil(CalendarMeeting.current(among: meetings, at: Date(timeIntervalSince1970: 2_000 - CalendarMeeting.joinToleranceSeconds - 1)))
    }

    func testCurrentExcludesAllDayAndEnded() {
        let meetings = [
            meeting("Todo el día", start: 0, end: 86_400, attendees: ["Ana"], allDay: true),
            meeting("Terminada", start: 0, end: 1_000)
        ]
        XCTAssertNil(CalendarMeeting.current(among: meetings, at: Date(timeIntervalSince1970: 2_000)))
    }

    func testCurrentPrefersMeetingWithAttendees() {
        let meetings = [
            meeting("Bloqueo foco", start: 0, end: 10_000),
            meeting("1:1 con Ana", start: 1_000, end: 3_000, attendees: ["Ana"])
        ]
        XCTAssertEqual(CalendarMeeting.current(among: meetings, at: Date(timeIntervalSince1970: 2_000))?.title, "1:1 con Ana")
    }

    func testOverlappingPicksLargestOverlap() {
        let meetings = [
            meeting("Corta", start: 0, end: 1_200),
            meeting("Larga", start: 1_000, end: 5_000)
        ]
        let match = CalendarMeeting.overlapping(
            among: meetings,
            from: Date(timeIntervalSince1970: 1_000),
            to: Date(timeIntervalSince1970: 4_000)
        )
        XCTAssertEqual(match?.title, "Larga")
    }

    func testOverlappingPrefersAttendeesOverLongerOverlap() {
        let meetings = [
            meeting("Bloqueo", start: 0, end: 10_000),
            meeting("Sync equipo", start: 3_000, end: 4_000, attendees: ["Ana", "Juan"])
        ]
        let match = CalendarMeeting.overlapping(
            among: meetings,
            from: Date(timeIntervalSince1970: 2_000),
            to: Date(timeIntervalSince1970: 5_000)
        )
        XCTAssertEqual(match?.title, "Sync equipo")
    }

    func testOverlappingReturnsNilWithoutIntersection() {
        let meetings = [meeting("Mañana", start: 10_000, end: 12_000)]
        XCTAssertNil(CalendarMeeting.overlapping(
            among: meetings,
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 5_000)
        ))
    }

    func testNameFromEmail() {
        XCTAssertEqual(CalendarMeeting.nameFromEmail("juan.perez@acme.com"), "Juan Perez")
        XCTAssertEqual(CalendarMeeting.nameFromEmail("mailto:ana_maria-lopez@x.co"), "Ana Maria Lopez")
        XCTAssertEqual(CalendarMeeting.nameFromEmail("usuario9@gmail.com"), "Usuario9")
        XCTAssertEqual(CalendarMeeting.nameFromEmail("mailto:sala.2@acme.com"), "Sala")
    }

    func testAttendeeNamePrefersRealName() {
        XCTAssertEqual(CalendarMeeting.attendeeName(name: "Ana López", address: "mailto:ana@x.co"), "Ana López")
        XCTAssertEqual(CalendarMeeting.attendeeName(name: "  ", address: "mailto:juan.perez@x.co"), "Juan Perez")
        XCTAssertEqual(CalendarMeeting.attendeeName(name: "ana@x.co", address: "mailto:ana@x.co"), "Ana")
        XCTAssertNil(CalendarMeeting.attendeeName(name: nil, address: nil))
    }

    func testUniqueAttendeesKeepsOrderCaseInsensitive() {
        XCTAssertEqual(
            CalendarMeeting.uniqueAttendees(["Ana", "Juan", "ana", "Ana López"]),
            ["Ana", "Juan", "Ana López"]
        )
    }

    func testParticipantsWikilinksAttendeesOrFallsBack() {
        let withPeople = meeting("Sync", start: 0, end: 100, attendees: ["Ana", "Juan"])
        XCTAssertEqual(
            CalendarMeeting.participants(meeting: withPeople, fallback: ["Yo", "Otros"]),
            ["[[Ana]]", "[[Juan]]"]
        )
        let empty = meeting("Bloqueo", start: 0, end: 100)
        XCTAssertEqual(CalendarMeeting.participants(meeting: empty, fallback: ["Yo", "Otros"]), ["Yo", "Otros"])
        XCTAssertEqual(CalendarMeeting.participants(meeting: nil, fallback: ["Yo"]), ["Yo"])
    }
}

extension CalendarLogicTests {

    func testCountdownFormats() {
        let meeting = CalendarMeeting(
            title: "Sync",
            start: Date(timeIntervalSince1970: 10_000),
            end: Date(timeIntervalSince1970: 13_600),
            attendees: [],
            isAllDay: false
        )
        XCTAssertEqual(meeting.countdown(at: Date(timeIntervalSince1970: 8_500)), "en 25 min")
        XCTAssertEqual(meeting.countdown(at: Date(timeIntervalSince1970: 2_800)), "en 2 h")
        XCTAssertEqual(meeting.countdown(at: Date(timeIntervalSince1970: 4_000)), "en 1 h 40 min")
        XCTAssertEqual(meeting.countdown(at: Date(timeIntervalSince1970: 11_000)), "ahora")
    }

    func testBarCountdownOnlyWithinAnHour() {
        let meeting = CalendarMeeting(
            title: "Sync",
            start: Date(timeIntervalSince1970: 10_000),
            end: Date(timeIntervalSince1970: 13_600),
            attendees: [],
            isAllDay: false
        )
        XCTAssertEqual(meeting.barCountdown(at: Date(timeIntervalSince1970: 9_100)), "15m")
        XCTAssertNil(meeting.barCountdown(at: Date(timeIntervalSince1970: 5_000)))
        XCTAssertNil(meeting.barCountdown(at: Date(timeIntervalSince1970: 10_001)))
    }
}

extension CalendarLogicTests {

    func testVideoLinkExtraction() {
        XCTAssertEqual(
            CalendarMeeting.videoLink(in: ["Unirse: https://meet.google.com/abc-defg-hij y llegar puntual"]),
            "https://meet.google.com/abc-defg-hij"
        )
        XCTAssertEqual(
            CalendarMeeting.videoLink(in: [nil, "ver notas https://acme.com/doc", "<https://us02web.zoom.us/j/123?pwd=x>"]),
            "https://us02web.zoom.us/j/123?pwd=x"
        )
        XCTAssertNotNil(CalendarMeeting.videoLink(in: ["https://teams.microsoft.com/l/meetup-join/xyz"]))
        XCTAssertNil(CalendarMeeting.videoLink(in: ["sin links", nil, "https://acme.com/agenda"]))
        XCTAssertNil(CalendarMeeting.videoLink(in: []))
    }

    func testFilteredIgnoreNoParticipants() {
        let blocker = meeting("Foco", start: 0, end: 100)
        let withPeople = meeting("Sync", start: 0, end: 100, attendees: ["Ana"])
        var withLink = meeting("Standup", start: 0, end: 100)
        withLink.videoLink = "https://meet.google.com/xyz"

        XCTAssertEqual(CalendarMeeting.filtered([blocker, withPeople, withLink], ignoreNoParticipants: false).count, 3)
        XCTAssertEqual(
            CalendarMeeting.filtered([blocker, withPeople, withLink], ignoreNoParticipants: true).map(\.title),
            ["Sync", "Standup"]
        )
    }

    func testConfigValidatesIgnoreNoParticipants() throws {
        var config = AriaConfig()
        XCTAssertFalse(config.ignoreNoParticipants)
        try config.set(key: "ignoreNoParticipants", value: "true")
        XCTAssertTrue(config.ignoreNoParticipants)
        XCTAssertThrowsError(try config.set(key: "ignoreNoParticipants", value: "tal vez"))
    }
}

extension CalendarLogicTests {

    func testIsIgnoredCaseInsensitiveTrimmed() {
        let ignored = ["festivos de colombia", "birthdays"]
        XCTAssertTrue(CalendarMeeting.isIgnored(calendarTitle: "Festivos de Colombia", ignored: ignored))
        XCTAssertTrue(CalendarMeeting.isIgnored(calendarTitle: "  BIRTHDAYS  ", ignored: ignored))
        XCTAssertFalse(CalendarMeeting.isIgnored(calendarTitle: "Work", ignored: ignored))
        XCTAssertFalse(CalendarMeeting.isIgnored(calendarTitle: "Festivos", ignored: ignored))
    }

    func testConfigParsesCalendarIgnoreList() throws {
        var config = AriaConfig()
        XCTAssertEqual(config.ignoredCalendars, [])
        try config.set(key: "calendarIgnore", value: " Festivos de Colombia , Birthdays ,, ")
        XCTAssertEqual(config.ignoredCalendars, ["festivos de colombia", "birthdays"])
        try config.set(key: "calendarIgnore", value: "(ninguno)")
        XCTAssertEqual(config.ignoredCalendars, [])
    }
}
