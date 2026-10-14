import AppKit
import Foundation

enum ConsentManager {

    private static let consentKey = "aria.consent.accepted.v1"

    static var hasConsent: Bool {
        UserDefaults.standard.bool(forKey: consentKey)
    }

    static let consentText = """
    Aria va a grabar el audio del sistema y tu micrófono mientras esté activa la grabación, \
    siempre con un indicador visible en la barra de menú.

    Es TU responsabilidad obtener el consentimiento de los demás participantes antes de grabar. \
    Las leyes de grabación varían según la jurisdicción: si en la llamada hay personas de lugares \
    con consentimiento de dos partes (varios estados de EE. UU., países de la UE), aplica la más \
    estricta. Grabar reuniones de tu empresa puede chocar con su política interna — valídalo antes.

    El audio nunca sale de este Mac: la transcripción es local, y a Claude solo viaja texto \
    (transcript + notas) cuando el enhance está activo.
    """

    @MainActor
    static func requestIfNeeded() -> Bool {
        guard !hasConsent else { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Antes de tu primera grabación"
        alert.informativeText = consentText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Acepto y entiendo")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        UserDefaults.standard.set(true, forKey: consentKey)
        return true
    }
}
