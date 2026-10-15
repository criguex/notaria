import SwiftUI

/// Marco visual compartido por los avisos flotantes de NotarIA (MeetingPromptPanel,
/// StillThereWarningPanel): tarjeta de radio grande, aro de 1pt y sombra que se adaptan
/// a claro/oscuro con los tokens de marca (ver BrandColor) — mismo lenguaje en los dos,
/// igual que Granola usa una sola "shell" de tarjeta para todas sus variantes de toast
/// (nota 17 §c, vault Aria-Obsidian).
struct ToastCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(colorScheme == .dark ? BrandColor.grafito : BrandColor.papel)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(BrandColor.pizarra.opacity(colorScheme == .dark ? 0.35 : 0.18), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.5 : 0.16),
                radius: colorScheme == .dark ? 22 : 16,
                x: 0,
                y: 8
            )
    }
}

/// Botón de cierre discreto: invisible en reposo, solo aparece con el mouse encima de
/// la tarjeta — mismo comportamiento que el cierre del toast de reunión de Granola.
struct ToastCloseButton: View {
    var isHovering: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .background(Circle().fill(.regularMaterial))
        .foregroundStyle(.secondary)
        .opacity(isHovering ? 1 : 0)
        .allowsHitTesting(isHovering)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .offset(x: -7, y: 7)
        .accessibilityLabel("Cerrar aviso")
    }
}

/// Franja de cuenta atrás de 3pt pegada al borde inferior de la tarjeta, igual que la
/// barra de auto-aceptar de Granola (sin el auto-aceptar: aquí solo es indicador visual
/// del tiempo que queda en `StillThereWarningPanel`).
struct ToastCountdownBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 1.5)
                .fill(BrandColor.sello.opacity(0.75))
                .frame(width: geometry.size.width * fraction)
        }
        .frame(height: 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.pizarra.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
    }
}
