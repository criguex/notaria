import AppKit
import Foundation

final class MainWindowBridge {

    static let shared = MainWindowBridge()
    static let openNotificationName = Notification.Name("com.aria.capture.openMain")
    static let focusHoyNotificationName = Notification.Name("com.aria.capture.focusHoy")

    var openAction: (() -> Void)?

    func triggerOpenToHoy() {
        triggerOpen()
        NotificationCenter.default.post(name: Self.focusHoyNotificationName, object: nil)
    }

    private var hotKey: GlobalHotKey?
    private var observer: NSObjectProtocol?

    func activate() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.openNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.triggerOpen()
        }
        hotKey = GlobalHotKey.registerOpenAria { [weak self] in
            self?.triggerOpen()
        }
    }

    func triggerOpen() {
        NSApp.setActivationPolicy(.regular)
        if let icon = BrandAssets.appIcon() {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
        openAction?()
    }
}
