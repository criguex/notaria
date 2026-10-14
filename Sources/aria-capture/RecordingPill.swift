import AppKit
import SwiftUI

@MainActor
final class RecordingPillWindowController {

    static let shared = RecordingPillWindowController()

    static let pillSize = NSSize(width: 232, height: 180)

    private var panel: NSPanel?

    func show(controller: RecordingController, feed: LiveTranscriptFeed) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let view = RecordingPillView(
            controller: controller,
            feed: feed,
            onDrag: { [weak self] delta in self?.applyDrag(delta) },
            onDragEnded: { [weak self] in self?.persistPosition() }
        )
        panel.contentView = NSHostingView(rootView: view)
        restorePosition(panel: panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.pillSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func restorePosition(panel: NSPanel) {
        let stored = PillPositionStore.load()
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
        let clamped = stored.clamped(toScreenSize: screenSize, pillSize: Self.pillSize)
        panel.setFrameOrigin(NSPoint(x: clamped.x, y: clamped.y))
    }

    private func applyDrag(_ delta: CGSize) {
        guard let panel else { return }
        var origin = panel.frame.origin
        origin.x += delta.width
        origin.y -= delta.height
        panel.setFrameOrigin(origin)
    }

    private func persistPosition() {
        guard let panel else { return }
        PillPositionStore.save(PillPosition(x: panel.frame.origin.x, y: panel.frame.origin.y))
    }
}

struct RecordingPillView: View {
    @ObservedObject var controller: RecordingController
    let feed: LiveTranscriptFeed
    let onDrag: (CGSize) -> Void
    let onDragEnded: () -> Void

    @State private var hovering = false
    @State private var lines: [LiveTranscriptLine] = []
    @State private var pollTimer: Timer?
    @State private var lastTranslation: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            pillBar
            if hovering {
                transcriptBox
            }
        }
        .frame(width: RecordingPillWindowController.pillSize.width, alignment: .topLeading)
    }

    private var statusText: String {
        if controller.isPaused { return "En pausa" }
        return controller.recordingElapsed.isEmpty ? "Grabando" : "Grabando \(controller.recordingElapsed)"
    }

    private var pillBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(controller.isPaused ? BrandColor.pizarra : BrandColor.sello)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BrandColor.papel)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Button {
                MainWindowBridge.shared.triggerOpenToHoy()
            } label: {
                Image(systemName: "note.text")
                    .foregroundStyle(BrandColor.papel)
            }
            .buttonStyle(.plain)
            .help("Notas")
            Button {
                if controller.isPaused { controller.resumeRecording() } else { controller.pauseRecording() }
            } label: {
                Image(systemName: controller.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(BrandColor.papel)
            }
            .buttonStyle(.plain)
            .help(controller.isPaused ? "Reanudar" : "Pausar")
            Button {
                controller.stopAndGenerate()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .foregroundStyle(BrandColor.papel)
            }
            .buttonStyle(.plain)
            .help("Detener")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(BrandColor.grafito.opacity(0.9)))
        .onHover { isHovering in
            hovering = isHovering
            if isHovering {
                refreshLines()
                pollTimer?.invalidate()
                pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    refreshLines()
                }
            } else {
                pollTimer?.invalidate()
                pollTimer = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let delta = CGSize(
                        width: value.translation.width - lastTranslation.width,
                        height: value.translation.height - lastTranslation.height
                    )
                    lastTranslation = value.translation
                    onDrag(delta)
                }
                .onEnded { _ in
                    lastTranslation = .zero
                    onDragEnded()
                }
        )
    }

    private var transcriptBox: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                if controller.isPaused {
                    Text("En pausa — transcripción detenida")
                        .font(.caption2)
                        .foregroundStyle(BrandColor.papel.opacity(0.7))
                } else if lines.isEmpty {
                    Text("Escuchando…")
                        .font(.caption2)
                        .foregroundStyle(BrandColor.papel.opacity(0.7))
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text("\(line.speaker): \(line.text)")
                            .font(.caption2)
                            .foregroundStyle(BrandColor.papel.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 110)
        .background(RoundedRectangle(cornerRadius: 10).fill(BrandColor.grafito.opacity(0.9)))
    }

    private func refreshLines() {
        lines = feed.recentLines(limit: 6)
    }
}
