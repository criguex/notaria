import AppKit

/// Carga los assets de marca NotarIA empacados como recursos del paquete SPM
/// (ver notaria-brand/out/). No recolorea el glifo de la barra de menú: es una
/// imagen "template" y macOS la tiñe automáticamente según el tema.
enum BrandAssets {

    private static let menuBarGlyph: NSImage? = {
        guard
            let url1x = Bundle.module.url(forResource: "menubar-22", withExtension: "png"),
            let url2x = Bundle.module.url(forResource: "menubar-44", withExtension: "png"),
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
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// Glifo del sello NotarIA para el estado "en reposo" de la barra de menú.
    static func menuBarImage() -> NSImage? { menuBarGlyph }

    /// Ícono de marca para el Dock mientras la ventana principal está abierta.
    static func appIcon() -> NSImage? { dockIcon }
}
