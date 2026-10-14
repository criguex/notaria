import AppKit
import SwiftUI

@MainActor
final class StillThereWarningViewModel: ObservableObject {
    @Published var remainingSeconds: Int
    init(remainingSeconds: Int) { self.remainingSeconds = remainingSeconds }
}

@MainActor
final class StillThereWarningWindowController {

    static let shared = StillThereWarningWindowController()

    private var panel: NSPanel?
    private var viewModel: StillThereWarningViewModel?

    var isPresenting: Bool { panel != nil }

    func present(remainingSeconds: Int, onKeepGoing: @escaping () -> Void, onStop: @escaping () -> Void) {
        dismiss()
        let size = NSSize(width: 360, height: 128)
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
        let viewModel = StillThereWarningViewModel(remainingSeconds: remainingSeconds)
        let view = StillThereWarningView(
            viewModel: viewModel,
            onKeepGoing: { [weak self] in
                onKeepGoing()
                self?.dismiss()
            },
            onStop: { [weak self] in
                onStop()
                self?.dismiss()
            }
        )
        panel.contentView = NSHostingView(rootView: view)
        let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let margin: CGFloat = 16
        panel.setFrameOrigin(NSPoint(x: area.maxX - size.width - margin, y: area.maxY - size.height - margin))
        self.panel = panel
        self.viewModel = viewModel
        panel.orderFrontRegardless()
    }

    func updateCountdown(_ remainingSeconds: Int) {
        viewModel?.remainingSeconds = max(0, remainingSeconds)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        viewModel = nil
    }
}

struct StillThereWarningView: View {
    @ObservedObject var viewModel: StillThereWarningViewModel
    let onKeepGoing: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(BrandColor.sello)
                    .font(.title3)
                Text("¿Sigues en la reunión?").font(.headline).lineLimit(1)
                Spacer(minLength: 0)
            }
            Text("Sin audio del sistema. Se detendrá y se generará la nota en \(viewModel.remainingSeconds) s.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Detener", action: onStop)
                    .buttonStyle(.bordered)
                    .tint(BrandColor.pizarra)
                Button("Seguir grabando", action: onKeepGoing)
                    .buttonStyle(.borderedProminent)
                    .tint(BrandColor.sello)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 360, height: 128)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
    }
}
