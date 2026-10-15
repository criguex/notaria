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
        if let meeting = meetingNow, meeting.promptExcluded { return false }
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

    /// true si hay alguna señal activa de llamada o reunión ahora mismo
    /// (independiente de si se llegó a mostrar el aviso). Se usa para saber
    /// cuándo "soltar" el `lastKey` de dedupe: si no hay nada activo, el
    /// próximo aviso (aunque repita la misma app/calendario) debe volver a
    /// mostrarse — de lo contrario una llamada de Teams posterior sin evento
    /// de calendario asociado nunca vuelve a avisar porque su key
    /// ("call:Teams") es idéntica a la de la llamada anterior.
    static func hasActiveSignal(micInUse: Bool, callApps: [String], meetingNow: CalendarMeeting?) -> Bool {
        (micInUse && !callApps.isEmpty) || meetingNow != nil
    }

    static func updatedLastKey(
        micInUse: Bool,
        callApps: [String],
        meetingNow: CalendarMeeting?,
        lastKey: String?
    ) -> String? {
        hasActiveSignal(micInUse: micInUse, callApps: callApps, meetingNow: meetingNow) ? lastKey : nil
    }

    enum Decision: String {
        case autoStart = "auto-start"
        case prompted = "prompted"
        case dedupedSameSignal = "suppressed-dedupe"
        case excludedCalendar = "suppressed-excluded-calendar"
        case suppressedBusy = "suppressed-busy"
        case noSignal = "no-signal"
    }

    /// Clasifica, con todas las señales, qué hizo (o habría hecho) el detector
    /// en este tick — solo para diagnóstico/log, replica el orden real de
    /// `RecordingController` sin duplicar su estado mutable.
    static func decision(
        micInUse: Bool,
        callApps: [String],
        meetingNow: CalendarMeeting?,
        alwaysOn: Bool,
        isRecording: Bool,
        hasConsent: Bool,
        lastKey: String?
    ) -> Decision {
        if micInUse, alwaysOn, hasConsent, isRecording == false { return .autoStart }
        if let meeting = meetingNow, meeting.promptExcluded { return .excludedCalendar }
        guard shouldPrompt(
            micInUse: micInUse, callApps: callApps, meetingNow: meetingNow, alwaysOn: alwaysOn, isRecording: isRecording
        ) else {
            return (alwaysOn || isRecording) ? .suppressedBusy : .noSignal
        }
        let candidate = key(meetingNow: meetingNow, callApps: callApps)
        return candidate == lastKey ? .dedupedSameSignal : .prompted
    }

    static func promptTitle(meetingNow: CalendarMeeting?) -> String {
        guard let meeting = meetingNow else { return "¿Tomar notas con NotarIA?" }
        return "¿Tomar notas de \"\(meeting.title)\" con NotarIA?"
    }

    /// "HH:mm" de la hora de inicio, en el huso indicado (por defecto el del sistema).
    static func timeLabel(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "es_CO")
        return formatter.string(from: date)
    }

    /// Nombre corto de la plataforma de videollamada a partir del link del evento
    /// (reusa el mapa de dominios ya conocido de `BrowserMeetingDetector`), o `nil`
    /// si no hay link o no se reconoce el dominio.
    static func platformLabel(videoLink: String?) -> String? {
        guard let videoLink, !videoLink.isEmpty else { return nil }
        return BrowserMeetingDetector.provider(forURL: videoLink)
    }

    /// Subtítulo "hora · plataforma" para el aviso de reunión real (p.ej. "10:30 · Meet"),
    /// o `nil` cuando no hay una reunión de calendario concreta que mostrar.
    static func promptSubtitle(meetingNow: CalendarMeeting?, timeZone: TimeZone = .current) -> String? {
        guard let meeting = meetingNow else { return nil }
        let time = timeLabel(for: meeting.start, timeZone: timeZone)
        guard let platform = platformLabel(videoLink: meeting.videoLink) else { return time }
        return "\(time) · \(platform)"
    }
}
