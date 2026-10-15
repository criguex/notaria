import AppKit

/// Punto de acceso a la preferencia de sistema "Reduce Motion", aislado detrás de un
/// closure para poder sustituirlo en tests sin tocar AppKit real.
enum MotionPreference {
    static var reduceMotionEnabled: () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Decisiones puras de timing para la animación de entrada/salida de los avisos
/// flotantes (deslizar desde la derecha, igual que el toast de reunión de Granola:
/// spring de ~0.28s — ver nota 17 §c, Aria-Obsidian). Con Reduce Motion activado la
/// duración cae a 0: el aviso aparece/desaparece sin deslizarse.
enum ToastAnimation {
    static let slideDuration: TimeInterval = 0.28

    static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : slideDuration
    }
}
