import EventKit
import Foundation

/// Mapeo puro de `EKAuthorizationStatus` a lo que debe mostrar la UI (agenda
/// de "Hoy", tarjeta del menú, Ajustes): solo con `.fullAccess` hay acceso de
/// verdad, así que solo ahí tiene sentido decir "Sin reuniones". El resto de
/// estados necesita pedir acceso o mandar a Ajustes del Sistema — nunca
/// mostrar una agenda vacía sin explicar por qué.
enum CalendarAccessPolicy {

    static let systemSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"

    static func hasFullAccess(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess
    }

    static func shouldRequestOnLaunch(_ status: EKAuthorizationStatus) -> Bool {
        status == .notDetermined
    }

    static func action(for status: EKAuthorizationStatus) -> PermissionRowAction {
        switch status {
        case .fullAccess: return .none
        case .notDetermined: return .request
        default: return .openSystemSettings
        }
    }

    static func message(for status: EKAuthorizationStatus) -> String? {
        switch status {
        case .fullAccess: return nil
        case .notDetermined: return "Conecta tu calendario para ver tu agenda del día."
        default: return "NotarIA no tiene acceso a tu calendario."
        }
    }

    static func actionLabel(for status: EKAuthorizationStatus) -> String? {
        switch action(for: status) {
        case .none: return nil
        case .request: return "Conectar calendario"
        case .openSystemSettings: return "Abrir Ajustes del Sistema…"
        }
    }

    static func settingsLabel(for status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess: return "Concedido"
        case .notDetermined: return "Sin solicitar"
        case .writeOnly: return "Solo escritura — insuficiente"
        default: return "Denegado"
        }
    }

    /// Solo se puede confiar en una agenda vacía cuando hay acceso completo;
    /// con cualquier otro estado, "sin reuniones" sería un falso negativo.
    static func shouldShowEmptyAgenda(status: EKAuthorizationStatus, meetingsCount: Int) -> Bool {
        hasFullAccess(status) && meetingsCount == 0
    }
}
