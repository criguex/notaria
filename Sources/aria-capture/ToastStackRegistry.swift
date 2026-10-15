import AppKit

/// Coordina la posición de todos los avisos flotantes abiertos (MeetingPromptPanel,
/// StillThereWarningPanel) para que se apilen en la esquina superior derecha sin
/// solaparse (ver `ToastStackLayout`) y para que entren/salgan deslizándose desde la
/// derecha — igual que el stack de notificaciones de Granola (nota 17 §c, vault
/// Aria-Obsidian), pero sin su auto-aceptar temporizado.
@MainActor
final class ToastStackRegistry {

    static let shared = ToastStackRegistry()

    private var order: [ObjectIdentifier] = []
    private var panels: [ObjectIdentifier: NSPanel] = [:]

    /// Ubica `panel` en el slot que le corresponda al final del stack y lo muestra
    /// deslizándose desde el borde derecho de la pantalla (o sin animar si Reduce
    /// Motion está activo). `panel.frame.size` debe ya tener el tamaño final.
    func present(_ panel: NSPanel) {
        let id = ObjectIdentifier(panel)
        if !order.contains(id) { order.append(id) }
        panels[id] = panel

        let screenArea = Self.activeScreenArea()
        guard let finalOrigin = relayout(in: screenArea)[id] else { return }

        let reduceMotion = MotionPreference.reduceMotionEnabled()
        let duration = ToastAnimation.duration(reduceMotion: reduceMotion)
        panel.alphaValue = reduceMotion ? 1 : 0

        if duration <= 0 {
            panel.setFrameOrigin(finalOrigin)
            panel.orderFrontRegardless()
            return
        }

        let startOrigin = NSPoint(x: screenArea.maxX + 24, y: finalOrigin.y)
        panel.setFrameOrigin(startOrigin)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(finalOrigin)
            panel.animator().alphaValue = 1
        }
    }

    /// Quita `panel` del stack deslizándolo de vuelta hacia la derecha (o sin animar
    /// con Reduce Motion) y reacomoda a los que queden. Llama `completion` cuando ya
    /// se puede cerrar/liberar la ventana.
    func dismiss(_ panel: NSPanel, completion: @escaping () -> Void) {
        let id = ObjectIdentifier(panel)
        order.removeAll { $0 == id }
        panels.removeValue(forKey: id)

        let screenArea = Self.activeScreenArea()
        let reduceMotion = MotionPreference.reduceMotionEnabled()
        let duration = ToastAnimation.duration(reduceMotion: reduceMotion)

        if duration <= 0 {
            panel.orderOut(nil)
            completion()
        } else {
            let exitOrigin = NSPoint(x: screenArea.maxX + 24, y: panel.frame.origin.y)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrameOrigin(exitOrigin)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                completion()
            })
        }
        applyRelayout(relayout(in: screenArea), animated: !reduceMotion)
    }

    private func relayout(in screenArea: NSRect) -> [ObjectIdentifier: NSPoint] {
        let activeIDs = order
        let activePanels = activeIDs.compactMap { panels[$0] }
        guard !activePanels.isEmpty else { return [:] }
        let heights = activePanels.map { $0.frame.height }
        let width = activePanels.map { $0.frame.width }.max() ?? 360
        let slots = ToastStackLayout.slots(for: heights, width: width, in: screenArea)
        var result: [ObjectIdentifier: NSPoint] = [:]
        for (id, slot) in zip(activeIDs, slots) {
            result[id] = NSPoint(x: slot.x, y: slot.y)
        }
        return result
    }

    private func applyRelayout(_ targets: [ObjectIdentifier: NSPoint], animated: Bool) {
        for (id, origin) in targets {
            guard let panel = panels[id] else { continue }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = ToastAnimation.slideDuration
                    panel.animator().setFrameOrigin(origin)
                }
            } else {
                panel.setFrameOrigin(origin)
            }
        }
    }

    private static func activeScreenArea() -> NSRect {
        (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
    }
}
