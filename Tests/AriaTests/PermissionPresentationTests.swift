import AVFoundation
import EventKit
import XCTest
@testable import aria_capture

final class PermissionPresentationTests: XCTestCase {

    // MARK: - CalendarAccessPolicy

    func testCalendarFullAccessHidesMessageAndAction() {
        XCTAssertTrue(CalendarAccessPolicy.hasFullAccess(.fullAccess))
        XCTAssertNil(CalendarAccessPolicy.message(for: .fullAccess))
        XCTAssertNil(CalendarAccessPolicy.actionLabel(for: .fullAccess))
        XCTAssertEqual(CalendarAccessPolicy.action(for: .fullAccess), .none)
        XCTAssertEqual(CalendarAccessPolicy.settingsLabel(for: .fullAccess), "Concedido")
    }

    func testCalendarNotDeterminedOffersConnectAction() {
        XCTAssertFalse(CalendarAccessPolicy.hasFullAccess(.notDetermined))
        XCTAssertEqual(CalendarAccessPolicy.action(for: .notDetermined), .request)
        XCTAssertEqual(CalendarAccessPolicy.actionLabel(for: .notDetermined), "Conectar calendario")
        XCTAssertNotNil(CalendarAccessPolicy.message(for: .notDetermined))
        XCTAssertTrue(CalendarAccessPolicy.shouldRequestOnLaunch(.notDetermined))
    }

    func testCalendarDeniedRestrictedWriteOnlyOfferSystemSettings() {
        for status: EKAuthorizationStatus in [.denied, .restricted, .writeOnly] {
            XCTAssertFalse(CalendarAccessPolicy.hasFullAccess(status), "\(status)")
            XCTAssertEqual(CalendarAccessPolicy.action(for: status), .openSystemSettings, "\(status)")
            XCTAssertEqual(CalendarAccessPolicy.actionLabel(for: status), "Abrir Ajustes del Sistema…", "\(status)")
            XCTAssertEqual(CalendarAccessPolicy.message(for: status), "NotarIA no tiene acceso a tu calendario.", "\(status)")
            XCTAssertFalse(CalendarAccessPolicy.shouldRequestOnLaunch(status), "\(status)")
        }
    }

    func testCalendarShouldOnlyShowEmptyAgendaWithFullAccessAndZeroMeetings() {
        XCTAssertTrue(CalendarAccessPolicy.shouldShowEmptyAgenda(status: .fullAccess, meetingsCount: 0))
        XCTAssertFalse(CalendarAccessPolicy.shouldShowEmptyAgenda(status: .fullAccess, meetingsCount: 1))
        XCTAssertFalse(CalendarAccessPolicy.shouldShowEmptyAgenda(status: .notDetermined, meetingsCount: 0))
        XCTAssertFalse(CalendarAccessPolicy.shouldShowEmptyAgenda(status: .denied, meetingsCount: 0))
    }

    // MARK: - MicrophonePermissionPolicy

    func testMicrophoneAuthorizedHasNoAction() {
        XCTAssertEqual(MicrophonePermissionPolicy.statusLabel(.authorized), "Concedido")
        XCTAssertEqual(MicrophonePermissionPolicy.action(.authorized), .none)
        XCTAssertNil(MicrophonePermissionPolicy.actionLabel(.authorized))
    }

    func testMicrophoneNotDeterminedOffersRequestAction() {
        XCTAssertEqual(MicrophonePermissionPolicy.statusLabel(.notDetermined), "Sin solicitar")
        XCTAssertEqual(MicrophonePermissionPolicy.action(.notDetermined), .request)
        XCTAssertEqual(MicrophonePermissionPolicy.actionLabel(.notDetermined), "Conceder acceso")
    }

    func testMicrophoneDeniedRestrictedOfferSystemSettings() {
        for status: AVAuthorizationStatus in [.denied, .restricted] {
            XCTAssertEqual(MicrophonePermissionPolicy.statusLabel(status), "Denegado", "\(status)")
            XCTAssertEqual(MicrophonePermissionPolicy.action(status), .openSystemSettings, "\(status)")
            XCTAssertEqual(MicrophonePermissionPolicy.actionLabel(status), "Abrir Ajustes del Sistema…", "\(status)")
        }
    }

    // MARK: - ScreenRecordingPermissionPolicy

    func testScreenRecordingGrantedHasNoAction() {
        XCTAssertEqual(ScreenRecordingPermissionPolicy.statusLabel(granted: true), "Concedido")
        XCTAssertEqual(ScreenRecordingPermissionPolicy.action(granted: true), .none)
        XCTAssertNil(ScreenRecordingPermissionPolicy.actionLabel(granted: true))
    }

    func testScreenRecordingNotGrantedOffersRequestAction() {
        XCTAssertEqual(ScreenRecordingPermissionPolicy.statusLabel(granted: false), "Denegado")
        XCTAssertEqual(ScreenRecordingPermissionPolicy.action(granted: false), .request)
        XCTAssertEqual(ScreenRecordingPermissionPolicy.actionLabel(granted: false), "Conceder acceso")
    }
}
