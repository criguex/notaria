import Foundation

enum MeetingNotifier {

    static func key(for meeting: CalendarMeeting) -> String {
        "\(meeting.title)|\(Int(meeting.start.timeIntervalSince1970))"
    }

    static func pendingKey(
        meetingNow: CalendarMeeting?,
        callDetected: Bool,
        alwaysOn: Bool,
        lastKey: String?
    ) -> String? {
        guard let meeting = meetingNow, callDetected, !alwaysOn else { return nil }
        let candidate = key(for: meeting)
        return candidate == lastKey ? nil : candidate
    }

    static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func scriptLine(for meeting: CalendarMeeting) -> String {
        "display notification \"Parece que estás en \\\"\(escaped(meeting.title))\\\". Abre el menú de NotarIA para grabarla.\" with title \"NotarIA\" sound name \"Glass\""
    }

    static func notify(_ meeting: CalendarMeeting) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", scriptLine(for: meeting)]
        try? process.run()
    }
}
