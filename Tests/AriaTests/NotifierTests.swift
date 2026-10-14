import XCTest
@testable import aria_capture

final class NotifierTests: XCTestCase {

    private let meeting = CalendarMeeting(
        title: "Sync \"Q3\"",
        start: Date(timeIntervalSince1970: 1_754_000_000),
        end: Date(timeIntervalSince1970: 1_754_003_600),
        attendees: ["Ana"],
        isAllDay: false
    )

    func testPendingKeyRequiresMeetingAndCallWithoutAlwaysOn() {
        XCTAssertNil(MeetingNotifier.pendingKey(meetingNow: nil, callDetected: true, alwaysOn: false, lastKey: nil))
        XCTAssertNil(MeetingNotifier.pendingKey(meetingNow: meeting, callDetected: false, alwaysOn: false, lastKey: nil))
        XCTAssertNil(MeetingNotifier.pendingKey(meetingNow: meeting, callDetected: true, alwaysOn: true, lastKey: nil))
        XCTAssertEqual(
            MeetingNotifier.pendingKey(meetingNow: meeting, callDetected: true, alwaysOn: false, lastKey: nil),
            "Sync \"Q3\"|1754000000"
        )
    }

    func testPendingKeyDedupesPerMeetingInstance() {
        let key = MeetingNotifier.key(for: meeting)
        XCTAssertNil(MeetingNotifier.pendingKey(meetingNow: meeting, callDetected: true, alwaysOn: false, lastKey: key))

        var nextWeek = meeting
        nextWeek.start = meeting.start.addingTimeInterval(7 * 86_400)
        XCTAssertNotNil(MeetingNotifier.pendingKey(meetingNow: nextWeek, callDetected: true, alwaysOn: false, lastKey: key))
    }

    func testScriptLineEscapesTitle() {
        let line = MeetingNotifier.scriptLine(for: meeting)
        XCTAssertTrue(line.contains("with title \"NotarIA\""))
        XCTAssertTrue(line.contains("Sync \\\"Q3\\\""))
        XCTAssertTrue(line.hasPrefix("display notification"))
    }
}
