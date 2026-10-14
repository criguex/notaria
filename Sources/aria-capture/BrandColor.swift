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
}
