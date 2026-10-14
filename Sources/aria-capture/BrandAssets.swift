import AppKit

/// Carga los assets de marca NotarIA empacados como recursos del paquete SPM
/// (ver notaria-brand/out/). No recolorea el glifo de la barra de menú: es una
/// imagen "template" y macOS la tiñe automáticamente según el tema.
enum BrandAssets {

    /// `Bundle.module` busca el .bundle de SwiftPM junto a `Bundle.main.bundleURL`,
    /// pero un .app firmado solo puede tener Contents/ en su raíz (codesign rechaza
    /// cualquier otra cosa) y `Bundle.module` revienta con fatalError si no encuentra
    /// nada. Empaquetados (ver scripts/package-app.sh) los recursos quedan copiados
    /// tal cual en Contents/Resources; ahí se buscan primero y nunca se toca
    /// Bundle.module en ese caso. Fuera del .app (CLI de desarrollo) el camino es
    /// exactamente el de siempre.
    private static func resourceURL(_ name: String, withExtension ext: String) -> URL? {
        guard LoginItemManager.isRunningFromAppBundle else {
            return Bundle.module.url(forResource: name, withExtension: ext)
        }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("\(name).\(ext)"),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    private static let menuBarGlyph: NSImage? = {
        guard
            let url1x = resourceURL("menubar-22", withExtension: "png"),
            let url2x = resourceURL("menubar-44", withExtension: "png"),
            let rep1x = NSImage(contentsOf: url1x)?.representations.first,
            let rep2x = NSImage(contentsOf: url2x)?.representations.first
        else { return nil }
        let image = NSImage(size: NSSize(width: 22, height: 22))
        rep1x.size = NSSize(width: 22, height: 22)
        rep2x.size = NSSize(width: 22, height: 22)
        image.addRepresentation(rep1x)
        image.addRepresentation(rep2x)
        image.isTemplate = true
        return image
    }()

    private static let dockIcon: NSImage? = {
        guard let url = resourceURL("AppIcon", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// Glifo del sello NotarIA para el estado "en reposo" de la barra de menú.
    static func menuBarImage() -> NSImage? { menuBarGlyph }

    /// Ícono de marca para el Dock mientras la ventana principal está abierta.
    static func appIcon() -> NSImage? { dockIcon }
}
