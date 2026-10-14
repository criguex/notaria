import AppKit
import Foundation

enum BrowserMeetingDetector {

    static let supportedBrowsers: [String: String] = [
        "com.google.Chrome": "Google Chrome",
        "com.apple.Safari": "Safari",
        "com.microsoft.edgemac": "Microsoft Edge",
        "company.thebrowser.Browser": "Arc"
    ]

    static let providerNames: [String: String] = [
        "meet.google.com": "Meet",
        "zoom.us": "Zoom",
        "teams.microsoft.com": "Teams",
        "teams.live.com": "Teams",
        "webex.com": "Webex",
        "whereby.com": "Whereby",
        "discord.gg": "Discord"
    ]

    static func provider(forURL url: String) -> String? {
        guard let link = CalendarMeeting.videoLink(in: [url]) else { return nil }
        for (domain, name) in providerNames where link.contains(domain) {
            return name
        }
        return nil
    }

    static func labels(forTabURLs urls: [String], browserName: String) -> [String] {
        let names = Set(urls.compactMap(provider(forURL:)))
        return names.sorted().map { "\($0) (\(browserName))" }
    }

    static func runningBrowsers() -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier, let name = supportedBrowsers[bundleID] else { return nil }
            return (bundleID, name)
        }
    }

    static func activeMeetingLabels() -> [String] {
        runningBrowsers().flatMap { labels(forTabURLs: tabURLs(forBrowser: $0.name), browserName: $0.name) }
    }

    static func tabURLs(forBrowser name: String) -> [String] {
        let script = "tell application \"\(name)\" to get URL of every tab of every window"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
