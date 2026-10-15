import ApplicationServices
import AppKit
import Foundation

enum AccessibilityPermission {
    static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Pide el permiso con el diálogo del sistema si no está concedido. Solo debe llamarse tras
    /// consentimiento explícito del usuario (toggle en Ajustes), nunca implícito al iniciar.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        guard !isGranted else { return true }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

/// Filtro puro (testeable) de candidatos a nombre de persona dentro de texto crudo leído de la UI
/// de una app de videollamada vía Accesibilidad: descarta chrome de UI (botones, timers, emails),
/// se queda con strings cortos tipo "Nombre Apellido".
enum ParticipantNameFilter {

    static let uiChromeWords: Set<String> = [
        "mute", "unmute", "chat", "more", "leave", "participants", "host", "cohost", "waiting",
        "recording", "share", "screen", "reactions", "raise", "hand", "end", "meeting",
        "silenciar", "activar", "salir", "anfitrión", "organizador", "grabando", "compartir",
        "pantalla", "reacciones", "levantar", "mano", "terminar", "reunión", "sala", "espera"
    ]

    static func plausibleNames(from strings: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in strings {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPlausibleName(trimmed), seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    static func isPlausibleName(_ text: String) -> Bool {
        guard text.count >= 2, text.count <= 60 else { return false }
        guard !text.contains("@"), !text.contains(":"), !text.contains("http") else { return false }
        guard text.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        let lowered = text.lowercased()
        guard !uiChromeWords.contains(where: { lowered == $0 || lowered.contains($0) }) else { return false }
        let words = text.split(separator: " ").map(String.init)
        guard (1...4).contains(words.count) else { return false }
        guard words.allSatisfy({ $0.first?.isLetter == true }) else { return false }
        return words.contains { $0.first?.isUppercase == true }
    }
}

/// Capa 2c (opt-in, apagado por defecto, `AriaConfig.participantsAccessibilityEnabled`): lee la
/// lista de participantes de la ventana de Zoom/Teams vía AXUIElement — solo nombres, nada más.
/// Mejor esfuerzo: la jerarquía AX de cada app cambia entre versiones y no se puede validar sin
/// abrir una llamada real (prohibido en esta sesión); si no encuentra nada reconocible, devuelve
/// vacío sin romper nada (misma filosofía de fallback que el resto de capas).
final class MeetingParticipantsAccessibilityReader {

    static let knownBundleIdentifiers: Set<String> = ["us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams"]

    func readParticipantNames() -> [String] {
        guard AccessibilityPermission.isGranted else { return [] }
        let candidates = NSWorkspace.shared.runningApplications.filter {
            guard let bundleID = $0.bundleIdentifier else { return false }
            return Self.knownBundleIdentifiers.contains(bundleID)
        }
        var names: [String] = []
        for app in candidates {
            names.append(contentsOf: collectStaticTextValues(pid: app.processIdentifier))
        }
        return ParticipantNameFilter.plausibleNames(from: names)
    }

    /// Recorre el árbol AX de la app hasta cierta profundidad recolectando valores de texto.
    private func collectStaticTextValues(pid: pid_t, maxDepth: Int = 6, maxNodes: Int = 2_000) -> [String] {
        let appElement = AXUIElementCreateApplication(pid)
        var collected: [String] = []
        var visited = 0
        collect(element: appElement, depth: 0, maxDepth: maxDepth, visited: &visited, maxNodes: maxNodes, into: &collected)
        return collected
    }

    private func collect(element: AXUIElement, depth: Int, maxDepth: Int, visited: inout Int, maxNodes: Int, into collected: inout [String]) {
        guard depth <= maxDepth, visited < maxNodes else { return }
        visited += 1

        var value: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty {
            collected.append(text)
        }
        var title: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title) == .success,
           let text = title as? String, !text.isEmpty {
            collected.append(text)
        }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }
        for child in children {
            collect(element: child, depth: depth + 1, maxDepth: maxDepth, visited: &visited, maxNodes: maxNodes, into: &collected)
        }
    }
}
