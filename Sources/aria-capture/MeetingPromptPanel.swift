import AppKit
import SwiftUI

@MainActor
final class MeetingPromptWindowController {

    static let shared = MeetingPromptWindowController()

    private var panel: NSPanel?

    func present(title: String, onStart: @escaping () -> Void) {
        dismiss()
        let size = NSSize(width: 360, height: 112)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = MeetingPromptView(
            title: title,
            onStart: { [weak self] in
                onStart()
                self?.dismiss()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        panel.contentView = NSHostingView(rootView: view)
        let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let margin: CGFloat = 16
        panel.setFrameOrigin(NSPoint(x: area.maxX - size.width - margin, y: area.maxY - size.height - margin))
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct MeetingPromptView: View {
    let title: String
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(BrandColor.sello)
                    .font(.title3)
                Text(title).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption.bold())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Text("No se grabará nada hasta que elijas \"Grabar\".")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Ignorar", action: onDismiss)
                    .buttonStyle(.bordered)
                    .tint(BrandColor.pizarra)
                Button("Grabar", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .tint(BrandColor.sello)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 360, height: 112)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
    }
}
