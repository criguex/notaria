import AppKit
import CoreAudio
import Foundation

struct CallSignal {
    let micInUse: Bool
    let callApps: [String]
    let meetingNow: CalendarMeeting?

    var probableCall: Bool { micInUse }
    var confirmedMeeting: Bool { micInUse && meetingNow != nil }

    var summary: String {
        var parts: [String] = []
        parts.append(micInUse ? "micrófono EN USO por alguna app" : "micrófono libre")
        parts.append(callApps.isEmpty ? "sin apps de llamadas abiertas" : "apps de llamadas: \(callApps.joined(separator: ", "))")
        if let meeting = meetingNow {
            parts.append("en calendario AHORA: \(meeting.title)")
        } else {
            parts.append("calendario: \(MeetingCalendar.isAuthorized ? "sin reuniones ahora" : MeetingCalendar.statusDescription)")
        }
        return parts.joined(separator: " · ")
    }
}

enum CallDetector {

    static let knownCallApps: [String: String] = [
        "com.microsoft.teams2": "Teams",
        "com.microsoft.teams": "Teams",
        "us.zoom.xos": "Zoom",
        "Cisco-Systems.Spark": "Webex",
        "com.webex.meetingmanager": "Webex",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.apple.FaceTime": "FaceTime",
        "com.hnc.Discord": "Discord"
    ]

    static func currentSignal() -> CallSignal {
        CallSignal(
            micInUse: defaultInputInUse(),
            callApps: runningCallApps() + BrowserMeetingDetector.activeMeetingLabels(),
            meetingNow: MeetingCalendar.shared.currentMeeting()
        )
    }

    static func runningCallApps() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return knownCallApps[bundleID]
        }
    }

    static func defaultInputInUse() -> Bool {
        var deviceID = AudioDeviceID(0)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &deviceSize, &deviceID
        ) == noErr, deviceID != 0 else {
            return false
        }

        var running = UInt32(0)
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(deviceID, &runningAddress, 0, nil, &runningSize, &running) == noErr else {
            return false
        }
        return running != 0
    }
}
