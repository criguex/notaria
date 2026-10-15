import Foundation

/// Texto del ítem de la barra de menú para la reunión en curso o próxima (≤60 min):
/// título corto truncado + cuenta atrás ("Sync QA · en 12 min" / "Sync QA · ahora").
/// `nil` en reposo — ahí solo se muestra el glifo, sin texto.
enum MenuBarMeetingTitle {

    static let maxLength = 22
    private static let separator = " · "

    static func text(meetingNow: CalendarMeeting?, upcoming: CalendarMeeting?, at date: Date) -> String? {
        if let meetingNow {
            return truncated(title: meetingNow.title, countdown: "ahora")
        }
        guard let upcoming else { return nil }
        let seconds = upcoming.start.timeIntervalSince(date)
        guard seconds > 0, seconds <= 3_600 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        return truncated(title: upcoming.title, countdown: "en \(minutes) min")
    }

    static func truncated(title: String, countdown: String, maxLength: Int = MenuBarMeetingTitle.maxLength) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = "\(cleanTitle)\(separator)\(countdown)"
        guard full.count > maxLength else { return full }
        let fixedLength = separator.count + countdown.count
        let titleBudget = maxLength - fixedLength - 1
        guard titleBudget > 0 else { return String(countdown.suffix(maxLength)) }
        let clipped = String(cleanTitle.prefix(titleBudget))
        return "\(clipped)…\(separator)\(countdown)"
    }
}
