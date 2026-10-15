import Foundation

enum AriaHome {
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var applicationSupportDirectory: URL {
        directory.appendingPathComponent("Library/Application Support", isDirectory: true)
    }
}
