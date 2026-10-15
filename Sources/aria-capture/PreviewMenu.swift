import AppKit
import Foundation
import SwiftUI

/// `aria-capture preview-menu` — muestra la tarjeta "Próxima reunión" del menú
/// desplegable en un panel flotante con datos de ejemplo durante unos segundos.
/// No graba nada, no abre links, no toca el calendario real.
@MainActor
enum PreviewMenu {

    static let previewSeconds: TimeInterval = 8

    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let meeting = CalendarMeeting(
            title: "Sync semanal: QA + producto",
            start: Date().addingTimeInterval(720),
            end: Date().addingTimeInterval(2_520),
            attendees: ["Ana", "Luis", "Marcela", "Jorge"],
            isAllDay: false,
            videoLink: "https://meet.google.com/aaa-bbbb-ccc"
        )
        let card = MeetingCardBuilder.build(meeting: meeting, at: Date(), nativeAppInstalled: false)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 300, height: 180)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: MeetingCardView(viewModel: card, onJoin: {}, onJoinAndTakeNotes: {}))
        panel.center()
        panel.orderFrontRegardless()

        print("[preview-menu] Tarjeta 'Próxima reunión' de ejemplo durante \(Int(previewSeconds))s — no se grabará ni abrirá nada.")
        RunLoop.current.run(until: Date().addingTimeInterval(previewSeconds))
        panel.orderOut(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        exit(0)
    }
}
