import Foundation
import ServiceManagement

enum LoginItemManager {

    static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isRunningFromAppBundle else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        guard isRunningFromAppBundle else {
            return "No disponible: estás corriendo el binario suelto, no NotarIA.app instalada."
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Activado"
        case .requiresApproval:
            return "Pendiente de aprobación en Ajustes del Sistema → General → Elementos de inicio de sesión"
        case .notFound:
            return "No registrado"
        case .notRegistered:
            return "Desactivado"
        @unknown default:
            return "Desconocido"
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        guard isRunningFromAppBundle else {
            return "Solo funciona desde NotarIA.app instalada (p.ej. en /Applications), no desde el binario de desarrollo."
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
