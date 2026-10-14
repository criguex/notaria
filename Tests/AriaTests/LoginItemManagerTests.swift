import XCTest
@testable import aria_capture

final class LoginItemManagerTests: XCTestCase {

    func testNotRunningFromAppBundleInTests() {
        XCTAssertFalse(LoginItemManager.isRunningFromAppBundle)
        XCTAssertFalse(LoginItemManager.isEnabled)
    }

    func testStatusDescriptionExplainsUnavailability() {
        XCTAssertTrue(LoginItemManager.statusDescription.contains("No disponible"))
    }

    func testSetEnabledReturnsMessageWhenNotFromAppBundle() {
        XCTAssertNotNil(LoginItemManager.setEnabled(true))
        XCTAssertNotNil(LoginItemManager.setEnabled(false))
    }
}
