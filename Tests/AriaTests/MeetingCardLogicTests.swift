import XCTest
@testable import aria_capture

final class MeetingCardLogicTests: XCTestCase {

    private func meeting(
        title: String = "Sync QA",
        attendees: [String] = [],
        videoLink: String? = nil
    ) -> CalendarMeeting {
        CalendarMeeting(
            title: title,
            start: Date(timeIntervalSince1970: 10_000),
            end: Date(timeIntervalSince1970: 13_600),
            attendees: attendees,
            isAllDay: false,
            videoLink: videoLink
        )
    }

    // MARK: - attendeesLabel

    func testAttendeesLabelNilWhenEmpty() {
        XCTAssertNil(MeetingCardBuilder.attendeesLabel([]))
    }

    func testAttendeesLabelJoinsUpToMax() {
        XCTAssertEqual(MeetingCardBuilder.attendeesLabel(["Ana", "Luis"]), "Ana, Luis")
        XCTAssertEqual(MeetingCardBuilder.attendeesLabel(["Ana", "Luis", "Marcela"]), "Ana, Luis, Marcela")
    }

    func testAttendeesLabelTruncatesWithPlusCount() {
        XCTAssertEqual(
            MeetingCardBuilder.attendeesLabel(["Ana", "Luis", "Marcela", "Jorge", "Pedro"]),
            "Ana, Luis, Marcela +2"
        )
    }

    func testAttendeesLabelRespectsCustomMaxShown() {
        XCTAssertEqual(MeetingCardBuilder.attendeesLabel(["Ana", "Luis", "Marcela"], maxShown: 1), "Ana +2")
    }

    // MARK: - build

    func testBuildWithoutLinkHasNoJoinURL() {
        let card = MeetingCardBuilder.build(
            meeting: meeting(attendees: ["Ana"]),
            at: Date(timeIntervalSince1970: 0),
            nativeAppInstalled: false
        )
        XCTAssertNil(card.joinURL)
        XCTAssertFalse(card.canJoin)
        XCTAssertNil(card.platformLabel)
        XCTAssertEqual(card.attendeesLabel, "Ana")
    }

    func testBuildWithLinkResolvesJoinURLAndPlatform() {
        let card = MeetingCardBuilder.build(
            meeting: meeting(videoLink: "https://meet.google.com/aaa-bbbb-ccc"),
            at: Date(timeIntervalSince1970: 0),
            nativeAppInstalled: false
        )
        XCTAssertEqual(card.joinURL?.absoluteString, "https://meet.google.com/aaa-bbbb-ccc")
        XCTAssertTrue(card.canJoin)
        XCTAssertEqual(card.platformLabel, "Meet")
    }

    func testBuildUsesTimeZoneForTimeLabel() {
        let card = MeetingCardBuilder.build(
            meeting: meeting(),
            at: Date(timeIntervalSince1970: 0),
            nativeAppInstalled: false,
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertEqual(card.timeLabel, MeetingPromptDecider.timeLabel(for: Date(timeIntervalSince1970: 10_000), timeZone: TimeZone(identifier: "UTC")!))
    }
}
