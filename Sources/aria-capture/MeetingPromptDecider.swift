import Foundation

enum MeetingPromptDecider {

    static func key(meetingNow: CalendarMeeting?, callApps: [String]) -> String {
        if let meeting = meetingNow {
            return "cal:\(MeetingNotifier.key(for: meeting))"
        }
        return "call:\(callApps.sorted().joined(separator: ","))"
    }

    static func shouldPrompt(
        micInUse: Bool,
        callApps: [String],
        meetingNow: CalendarMeeting?,
        alwaysOn: Bool,
        isRecording: Bool
    ) -> Bool {
        guard !alwaysOn, !isRecording else { return false }
        let callSignal = micInUse && !callApps.isEmpty
        return callSignal || meetingNow != nil
    }

    static func pendingKey(
        micInUse: Bool,
        callApps: [String],
        meetingNow: CalendarMeeting?,
        alwaysOn: Bool,
        isRecording: Bool,
        lastKey: String?
    ) -> String? {
        guard shouldPrompt(
            micInUse: micInUse,
            callApps: callApps,
            meetingNow: meetingNow,
            alwaysOn: alwaysOn,
            isRecording: isRecording
        ) else { return nil }
        let candidate = key(meetingNow: meetingNow, callApps: callApps)
        return candidate == lastKey ? nil : candidate
    }

    static func promptTitle(meetingNow: CalendarMeeting?) -> String {
        guard let meeting = meetingNow else { return "¿Tomar notas con NotarIA?" }
        return "¿Tomar notas de \"\(meeting.title)\" con NotarIA?"
    }
}
