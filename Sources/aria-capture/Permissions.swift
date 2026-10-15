import AVFoundation
import CoreGraphics
import Foundation

enum Permissions {

    static let screenSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    static let micSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"

    static func ensureMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("[tcc] Micrófono: concedido")
            return true
        case .notDetermined:
            print("[tcc] Micrófono: sin solicitar → pidiendo permiso ahora (acepta el diálogo)…")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            print("[tcc] Micrófono: \(granted ? "concedido" : "denegado")")
            return granted
        default:
            print("[tcc] Micrófono: DENEGADO. Habilita tu terminal y vuelve a correr:")
            print("      open \"\(micSettingsURL)\"")
            return false
        }
    }

    static func ensureScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            print("[tcc] Grabación de pantalla: concedido")
            return true
        }
        print("[tcc] Grabación de pantalla: no concedido → pidiendo permiso ahora…")
        if CGRequestScreenCaptureAccess() {
            print("[tcc] Grabación de pantalla: concedido")
            return true
        }
        print("[tcc] Grabación de pantalla: DENEGADO. Habilita tu terminal (macOS exige relanzarla) y vuelve a correr:")
        print("      open \"\(screenSettingsURL)\"")
        return false
    }

    static func ensureAll(dictationOnly: Bool = false) async -> Bool {
        let mic = await ensureMicrophone()
        guard RequiredPermissions.needsScreenRecording(dictationOnly: dictationOnly) else { return mic }
        let screen = ensureScreenRecording()
        return mic && screen
    }

    static func microphoneStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func screenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}

enum RequiredPermissions {
    static func needsScreenRecording(dictationOnly: Bool) -> Bool {
        !dictationOnly
    }
}

/// Acción que debe ofrecer la fila de un permiso en Ajustes, derivada del
/// estado real — nunca se pide Grabación de pantalla sola a ciegas, solo se
/// decide qué botón mostrar; quien pulsa decide si de verdad se pide.
enum PermissionRowAction: Equatable {
    case none
    case request
    case openSystemSettings
}

enum MicrophonePermissionPolicy {
    static func statusLabel(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Concedido"
        case .notDetermined: return "Sin solicitar"
        default: return "Denegado"
        }
    }

    static func action(_ status: AVAuthorizationStatus) -> PermissionRowAction {
        switch status {
        case .authorized: return .none
        case .notDetermined: return .request
        default: return .openSystemSettings
        }
    }

    static func actionLabel(_ status: AVAuthorizationStatus) -> String? {
        switch action(status) {
        case .none: return nil
        case .request: return "Conceder acceso"
        case .openSystemSettings: return "Abrir Ajustes del Sistema…"
        }
    }
}

enum ScreenRecordingPermissionPolicy {
    static func statusLabel(granted: Bool) -> String {
        granted ? "Concedido" : "Denegado"
    }

    static func action(granted: Bool) -> PermissionRowAction {
        granted ? .none : .request
    }

    static func actionLabel(granted: Bool) -> String? {
        granted ? nil : "Conceder acceso"
    }
}
