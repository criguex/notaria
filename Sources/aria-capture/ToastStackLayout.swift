import Foundation

/// Origen (convención AppKit: esquina inferior-izquierda) de un aviso flotante apilado.
struct ToastSlot: Equatable {
    var x: CGFloat
    var y: CGFloat
}

/// Matemática pura de apilado de avisos flotantes en la esquina superior derecha de
/// la pantalla, inspirada en el stack de notificaciones de Granola (misma esquina,
/// separación fija entre tarjetas, nunca se solapan) — ver nota
/// "17 - Detección de reuniones y Nub de Granola" §c (RE), vault Aria-Obsidian:
/// `x = workArea.maxX - width - margen`, `y` de cada aviso = el de arriba menos su
/// propia altura, y el siguiente aviso arranca `gap` por debajo de ese.
enum ToastStackLayout {

    /// Separación vertical entre avisos apilados.
    static let gap: CGFloat = 12
    /// Margen desde los bordes del área visible de la pantalla.
    static let edgeMargin: CGFloat = 16

    /// Calcula el origen de cada aviso apilado de arriba hacia abajo en `screenArea`,
    /// dado un ancho fijo común y la altura real de cada uno, en el orden en que se
    /// presentaron (el primero queda más arriba).
    static func slots(for heights: [CGFloat], width: CGFloat, in screenArea: CGRect) -> [ToastSlot] {
        var slots: [ToastSlot] = []
        var topY = screenArea.maxY - edgeMargin
        let x = screenArea.maxX - width - edgeMargin
        for height in heights {
            let y = topY - height
            slots.append(ToastSlot(x: x, y: y))
            topY = y - gap
        }
        return slots
    }
}
