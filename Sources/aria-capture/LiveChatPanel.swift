import AppKit
import SwiftUI

@MainActor
final class LiveChatPanelController {

    static let shared = LiveChatPanelController()
    static let panelSize = NSSize(width: 320, height: 380)

    private var panel: NSPanel?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(controller: RecordingController, feed: LiveTranscriptFeed) {
        if isVisible {
            hide()
        } else {
            show(controller: controller, feed: feed)
        }
    }

    func show(controller: RecordingController, feed: LiveTranscriptFeed) {
        guard let pillFrame = RecordingPillWindowController.shared.frame else { return }
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: Self.panelSize.width, height: Self.panelSize.height)
        let anchor = ChatPanelLayout.anchor(pillFrame: pillFrame, screenFrame: screenFrame, panelWidth: size.width)
        let origin = ChatPanelLayout.origin(pillFrame: pillFrame, screenFrame: screenFrame, panelSize: size, anchor: anchor)

        let panel = panel ?? makePanel()
        self.panel = panel
        let view = LiveChatPanelView(controller: controller, feed: feed, onClose: { [weak self] in self?.hide() })
        panel.contentView = NSHostingView(rootView: view)
        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
        panel.makeKeyAndOrderFront(nil)
        installClickOutsideMonitors()
    }

    func hide() {
        panel?.orderOut(nil)
        removeClickOutsideMonitors()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
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

    private func installClickOutsideMonitors() {
        removeClickOutsideMonitors()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in LiveChatPanelController.shared.handlePossibleOutsideClick(at: NSEvent.mouseLocation) }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            Task { @MainActor in LiveChatPanelController.shared.handlePossibleOutsideClick(at: NSEvent.mouseLocation) }
            return event
        }
    }

    private func removeClickOutsideMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }

    private func handlePossibleOutsideClick(at screenPoint: NSPoint) {
        guard let panel, panel.isVisible else { return }
        if panel.frame.contains(screenPoint) { return }
        if let pillFrame = RecordingPillWindowController.shared.frame, pillFrame.contains(screenPoint) { return }
        hide()
    }
}

struct LiveChatPanelView: View {
    @ObservedObject var controller: RecordingController
    let feed: LiveTranscriptFeed
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var items: [ChatTimelineItem] = []
    @State private var isAtBottom = true
    @State private var pollTimer: Timer?

    private static let bottomAnchorID = "aria-chat-bottom"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(items) { item in
                                row(for: item).transition(bubbleTransition)
                            }
                            if controller.isPaused {
                                openPauseChip
                            }
                            Color.clear
                                .frame(height: 1)
                                .id(Self.bottomAnchorID)
                                .onAppear { isAtBottom = true }
                                .onDisappear { isAtBottom = false }
                        }
                        .padding(12)
                    }
                    .onChange(of: items.count) {
                        if isAtBottom { scrollToBottom(proxy: proxy) }
                    }
                    .onAppear {
                        refresh()
                        scrollToBottom(proxy: proxy)
                        startPolling()
                    }
                    .onDisappear { stopPolling() }

                    if !isAtBottom {
                        Button("↓ Nuevos") {
                            scrollToBottom(proxy: proxy)
                            isAtBottom = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrandColor.sello)
                        .font(.caption.bold())
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .frame(width: LiveChatPanelController.panelSize.width, height: LiveChatPanelController.panelSize.height)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
        .onExitCommand { onClose() }
    }

    private var header: some View {
        HStack {
            Text("Conversación en vivo")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(headerText)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(headerText.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var openPauseChip: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ChatPauseChipView(label: openPauseLabel)
        }
    }

    private var openPauseLabel: String {
        guard let start = controller.pauseLog.openPauseStart else { return "En pausa" }
        let total = max(0, Int(Date().timeIntervalSince(start)))
        return "En pausa — \(String(format: "%d:%02d", total / 60, total % 60))"
    }

    @ViewBuilder
    private func row(for item: ChatTimelineItem) -> some View {
        switch item {
        case .messages(let group):
            ChatGroupBubbleView(group: group, themBackground: themBackground, themText: themText)
        case .pause(let interval):
            ChatPauseChipView(label: PauseLogic.rangeLabel(for: interval))
        }
    }

    private var panelBackground: Color { colorScheme == .dark ? BrandColor.grafito : BrandColor.papel }
    private var headerText: Color { colorScheme == .dark ? BrandColor.papel : BrandColor.tinta }
    private var themBackground: Color { colorScheme == .dark ? BrandColor.pizarra : BrandColor.arena }
    private var themText: Color { colorScheme == .dark ? BrandColor.papel : BrandColor.tinta }

    private var bubbleTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        )
    }

    private func refresh() {
        let lines = feed.recentLines(limit: 200)
        let next = ChatBubbleLogic.timeline(lines: lines, pauses: controller.pauseLog.intervals)
        guard next != items else { return }
        if reduceMotion {
            items = next
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                items = next
            }
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in refresh() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }
}

struct ChatGroupBubbleView: View {
    let group: ChatMessageGroup
    let themBackground: Color
    let themText: Color

    var body: some View {
        VStack(alignment: group.isYou ? .trailing : .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(group.speaker).font(.caption2.bold()).foregroundStyle(.secondary)
                Text(TranscriptFormatter.timestamp(group.startTimestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: group.isYou ? .trailing : .leading, spacing: 4) {
                ForEach(Array(group.messages.enumerated()), id: \.offset) { _, message in
                    Text(message.text)
                        .font(.system(size: 13))
                        .foregroundStyle(group.isYou ? BrandColor.papel : themText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(group.isYou ? BrandColor.sello : themBackground)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: group.isYou ? .trailing : .leading)
    }
}

struct ChatPauseChipView: View {
    let label: String

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Text("⏸ \(label)")
                .font(.caption2)
                .foregroundStyle(BrandColor.pizarra)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(BrandColor.pizarra.opacity(0.18)))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
