import Foundation

/// Fracción de avance (0...1) de la barra de cuenta atrás del aviso "¿Sigues ahí?",
/// pensada igual que la barra de 20s de Granola (ver nota 17 §c, Aria-Obsidian): arranca
/// en 0 y llega a 1 cuando se agota el tiempo restante, acotada siempre a 0...1 aunque
/// lleguen valores fuera de rango (reloj que se adelanta, `total` en 0, etc.).
enum ToastProgress {
    static func fraction(remaining: Int, total: Int) -> Double {
        guard total > 0 else { return remaining <= 0 ? 1 : 0 }
        let elapsed = Double(total - remaining)
        return min(1, max(0, elapsed / Double(total)))
    }
}
