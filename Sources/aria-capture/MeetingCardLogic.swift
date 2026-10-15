import Foundation

/// Datos ya resueltos para la tarjeta "Próxima reunión" del menú desplegable —
/// separa la lógica pura (truncar asistentes, elegir plataforma, resolver link)
/// de la vista SwiftUI que solo pinta estos campos.
struct MeetingCardViewModel: Equatable {
    let title: String
    let timeLabel: String
    let platformLabel: String?
    let attendeesLabel: String?
    let joinURL: URL?

    var canJoin: Bool { joinURL != nil }
}

enum MeetingCardBuilder {

    static func build(
        meeting: CalendarMeeting,
        at date: Date,
        nativeAppInstalled: Bool,
        timeZone: TimeZone = .current,
        maxAttendeesShown: Int = 3
    ) -> MeetingCardViewModel {
        let joinURL = meeting.videoLink.flatMap {
            MeetingJoinLink.resolve(videoLink: $0, nativeAppInstalled: nativeAppInstalled)
        }
        return MeetingCardViewModel(
            title: meeting.title,
            timeLabel: MeetingPromptDecider.timeLabel(for: meeting.start, timeZone: timeZone),
            platformLabel: MeetingPromptDecider.platformLabel(videoLink: meeting.videoLink),
            attendeesLabel: attendeesLabel(meeting.attendees, maxShown: maxAttendeesShown),
            joinURL: joinURL
        )
    }

    static func attendeesLabel(_ names: [String], maxShown: Int = 3) -> String? {
        guard !names.isEmpty else { return nil }
        guard names.count > maxShown else { return names.joined(separator: ", ") }
        let shown = names.prefix(maxShown).joined(separator: ", ")
        return "\(shown) +\(names.count - maxShown)"
    }
}
