import SwiftUI

extension Color {
    init(brandHex hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// Tokens de la identidad visual NotarIA (ver notaria-brand/BRAND.md).
/// Paleta plana, sin gradientes. Sello es el único acento.
enum BrandColor {
    static let tinta = Color(brandHex: 0x1E2A38)
    static let papel = Color(brandHex: 0xF3EEE4)
    static let sello = Color(brandHex: 0xAE4430)
    static let pizarra = Color(brandHex: 0x55606B)
    static let grafito = Color(brandHex: 0x14181D)
    static let arena = Color(brandHex: 0xD9CDB8)

    /// Texto principal sobre una tarjeta de aviso (Tinta en claro sobre Papel,
    /// Papel en oscuro sobre Grafito) — contraste correcto en los dos modos.
    static func toastTitle(for scheme: ColorScheme) -> Color { scheme == .dark ? papel : tinta }

    /// Texto secundario sobre una tarjeta de aviso (Pizarra en claro, Arena en
    /// oscuro: Pizarra pierde demasiado contraste sobre Grafito).
    static func toastSecondary(for scheme: ColorScheme) -> Color { scheme == .dark ? arena : pizarra }
}
