import XCTest
@testable import aria_capture

final class MeetingParticipantsAccessibilityTests: XCTestCase {

    func testPlausibleNamesKeepsTitleCaseShortNames() {
        let result = ParticipantNameFilter.plausibleNames(from: ["Ana García", "Juan"])
        XCTAssertEqual(result, ["Ana García", "Juan"])
    }

    func testPlausibleNamesDropsUIChrome() {
        let result = ParticipantNameFilter.plausibleNames(from: ["Mute", "Participants", "Leave meeting", "Silenciar"])
        XCTAssertTrue(result.isEmpty)
    }

    func testPlausibleNamesDropsEmailsAndTimers() {
        let result = ParticipantNameFilter.plausibleNames(from: ["ana@empresa.com", "00:12:34", "https://zoom.us/j/123"])
        XCTAssertTrue(result.isEmpty)
    }

    func testPlausibleNamesDropsLowercaseAndOverlyLongStrings() {
        XCTAssertFalse(ParticipantNameFilter.isPlausibleName("ana garcia"))
        XCTAssertFalse(ParticipantNameFilter.isPlausibleName(String(repeating: "A", count: 61)))
        XCTAssertFalse(ParticipantNameFilter.isPlausibleName("A"))
    }

    func testPlausibleNamesDedupesCaseInsensitively() {
        let result = ParticipantNameFilter.plausibleNames(from: ["Ana García", "ana garcía".capitalized, "Ana García"])
        XCTAssertEqual(result.count, 1)
    }

    func testAccessibilityPermissionSettingsURLIsWellFormed() {
        XCTAssertTrue(AccessibilityPermission.settingsURL.hasPrefix("x-apple.systempreferences:"))
    }
}
