import AppKit
import SwiftUI

@MainActor
final class MeetingPromptWindowController {

    static let shared = MeetingPromptWindowController()

    private var panel: NSPanel?

    func present(title: String, subtitle: String? = nil, joinURL: URL? = nil, onStart: @escaping () -> Void) {
        dismiss()
        let size = NSSize(width: 360, height: 118)
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
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = MeetingPromptView(
            title: title,
            subtitle: subtitle,
            joinURL: joinURL,
            onStart: { [weak self] in
                onStart()
                self?.dismiss()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        panel.contentView = NSHostingView(rootView: view)
        self.panel = panel
        // No roba foco: nunca se activa la app ni se vuelve key window.
        ToastStackRegistry.shared.present(panel)
    }

    func dismiss() {
        guard let panel else { return }
        self.panel = nil
        ToastStackRegistry.shared.dismiss(panel) {
            panel.contentView = nil
        }
    }
}

struct MeetingPromptView: View {
    let title: String
    let subtitle: String?
    var joinURL: URL? = nil
    let onStart: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    private func joinAndTakeNotes() {
        if let joinURL { NSWorkspace.shared.open(joinURL) }
        onStart()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(BrandColor.sello)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BrandColor.toastTitle(for: colorScheme))
                        .lineLimit(2)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(BrandColor.toastSecondary(for: colorScheme))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            Text(joinURL == nil ? "No se grabará nada hasta que elijas \"Grabar\"." : "No se grabará nada hasta que elijas una opción.")
                .font(.system(size: 11))
                .foregroundStyle(BrandColor.toastSecondary(for: colorScheme))
            HStack {
                Spacer()
                if joinURL != nil {
                    Button("Solo tomar notas", action: onStart)
                        .buttonStyle(.bordered)
                        .tint(BrandColor.pizarra)
                    Button("Unirse y tomar notas", action: joinAndTakeNotes)
                        .buttonStyle(.borderedProminent)
                        .tint(BrandColor.sello)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Ignorar", action: onDismiss)
                        .buttonStyle(.bordered)
                        .tint(BrandColor.pizarra)
                    Button("Grabar", action: onStart)
                        .buttonStyle(.borderedProminent)
                        .tint(BrandColor.sello)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(width: 360, height: 118, alignment: .topLeading)
        .background(ToastCardBackground())
        .overlay(alignment: .topLeading) {
            ToastCloseButton(isHovering: isHovering, action: onDismiss)
        }
        .onHover { hovering in isHovering = hovering }
    }
}
