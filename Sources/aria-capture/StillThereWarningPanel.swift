import AppKit
import SwiftUI

@MainActor
final class StillThereWarningViewModel: ObservableObject {
    @Published var remainingSeconds: Int
    let totalSeconds: Int
    init(remainingSeconds: Int, totalSeconds: Int) {
        self.remainingSeconds = remainingSeconds
        self.totalSeconds = max(1, totalSeconds)
    }
}

@MainActor
final class StillThereWarningWindowController {

    static let shared = StillThereWarningWindowController()

    private var panel: NSPanel?
    private var viewModel: StillThereWarningViewModel?

    var isPresenting: Bool { panel != nil }

    func present(
        remainingSeconds: Int,
        totalSeconds: Int = Int(RecordingSessionMachine.defaultCountdownSeconds),
        onKeepGoing: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        dismiss()
        let size = NSSize(width: 360, height: 132)
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
        let viewModel = StillThereWarningViewModel(remainingSeconds: remainingSeconds, totalSeconds: totalSeconds)
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
        self.panel = panel
        self.viewModel = viewModel
        ToastStackRegistry.shared.present(panel)
    }

    func updateCountdown(_ remainingSeconds: Int) {
        viewModel?.remainingSeconds = max(0, remainingSeconds)
    }

    func dismiss() {
        guard let panel else { return }
        self.panel = nil
        self.viewModel = nil
        ToastStackRegistry.shared.dismiss(panel) {
            panel.contentView = nil
        }
    }
}

struct StillThereWarningView: View {
    @ObservedObject var viewModel: StillThereWarningViewModel
    let onKeepGoing: () -> Void
    let onStop: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(BrandColor.sello)
                    .font(.title3)
                Text("¿Sigues en la reunión?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BrandColor.toastTitle(for: colorScheme))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text("Sin audio del sistema. Se detendrá y se generará la nota en \(viewModel.remainingSeconds) s.")
                .font(.system(size: 11))
                .foregroundStyle(BrandColor.toastSecondary(for: colorScheme))
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
        .padding(16)
        .frame(width: 360, height: 132, alignment: .topLeading)
        .background(ToastCardBackground())
        .overlay(alignment: .bottom) {
            ToastCountdownBar(
                fraction: ToastProgress.fraction(remaining: viewModel.remainingSeconds, total: viewModel.totalSeconds)
            )
            .padding(.horizontal, 3)
            .padding(.bottom, 3)
        }
    }
}
