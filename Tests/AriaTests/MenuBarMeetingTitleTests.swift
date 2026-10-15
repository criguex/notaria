import XCTest
@testable import aria_capture

final class MenuBarMeetingTitleTests: XCTestCase {

    private func meeting(title: String, start: TimeInterval, end: TimeInterval) -> CalendarMeeting {
        CalendarMeeting(title: title, start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end), attendees: [], isAllDay: false)
    }

    func testNilWhenNoMeetingAtAll() {
        XCTAssertNil(MenuBarMeetingTitle.text(meetingNow: nil, upcoming: nil, at: Date(timeIntervalSince1970: 1_000)))
    }

    func testOngoingMeetingShowsAhora() {
        let now = meeting(title: "Sync QA", start: 0, end: 10_000)
        let text = MenuBarMeetingTitle.text(meetingNow: now, upcoming: nil, at: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(text, "Sync QA · ahora")
    }

    func testOngoingMeetingTakesPriorityOverUpcoming() {
        let now = meeting(title: "Sync QA", start: 0, end: 10_000)
        let upcoming = meeting(title: "Otra", start: 1_200, end: 2_000)
        let text = MenuBarMeetingTitle.text(meetingNow: now, upcoming: upcoming, at: Date(timeIntervalSince1970: 500))
        XCTAssertEqual(text, "Sync QA · ahora")
    }

    func testUpcomingWithinHourShowsMinutesCountdown() {
        let upcoming = meeting(title: "Sync QA", start: 10_000, end: 13_600)
        let text = MenuBarMeetingTitle.text(meetingNow: nil, upcoming: upcoming, at: Date(timeIntervalSince1970: 9_280))
        XCTAssertEqual(text, "Sync QA · en 12 min")
    }

    func testUpcomingBeyondHourReturnsNil() {
        let upcoming = meeting(title: "Sync QA", start: 10_000, end: 13_600)
        XCTAssertNil(MenuBarMeetingTitle.text(meetingNow: nil, upcoming: upcoming, at: Date(timeIntervalSince1970: 5_000)))
    }

    func testUpcomingAlreadyStartedReturnsNil() {
        let upcoming = meeting(title: "Sync QA", start: 10_000, end: 13_600)
        XCTAssertNil(MenuBarMeetingTitle.text(meetingNow: nil, upcoming: upcoming, at: Date(timeIntervalSince1970: 10_001)))
    }

    func testTruncatedKeepsShortTitleUnchanged() {
        XCTAssertEqual(MenuBarMeetingTitle.truncated(title: "Sync QA", countdown: "en 12 min"), "Sync QA · en 12 min")
    }

    func testTruncatedClipsLongTitleToMaxLength() {
        let result = MenuBarMeetingTitle.truncated(title: "Sync semanal: QA + producto", countdown: "en 12 min")
        XCTAssertLessThanOrEqual(result.count, MenuBarMeetingTitle.maxLength)
        XCTAssertTrue(result.hasSuffix("· en 12 min"))
        XCTAssertTrue(result.contains("…"))
    }

    func testTruncatedWithAhoraCountdown() {
        let result = MenuBarMeetingTitle.truncated(title: "Sync semanal muy largo de verdad", countdown: "ahora")
        XCTAssertLessThanOrEqual(result.count, MenuBarMeetingTitle.maxLength)
        XCTAssertTrue(result.hasSuffix("· ahora"))
    }

    func testTruncatedTrimsWhitespaceInTitle() {
        XCTAssertEqual(MenuBarMeetingTitle.truncated(title: "  Sync QA  ", countdown: "ahora"), "Sync QA · ahora")
    }

    func testConfigShowMenuBarTitleDefaultsToTrueAndValidates() throws {
        var config = AriaConfig()
        XCTAssertTrue(config.showMenuBarTitle)
        try config.set(key: "showMenuBarTitle", value: "false")
        XCTAssertFalse(config.showMenuBarTitle)
        XCTAssertThrowsError(try config.set(key: "showMenuBarTitle", value: "tal vez"))
    }
}
