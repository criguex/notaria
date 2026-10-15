import EventKit
import Foundation

struct CalendarMeeting: Equatable {
    var title: String
    var start: Date
    var end: Date
    var attendees: [String]
    var isAllDay: Bool
    var companies: [String] = []
    var videoLink: String? = nil
    /// true cuando el calendario/cuenta de origen tiene "Ofrecer grabar" apagado
    /// (ver `CalendarPromptPolicy`): no debe disparar el aviso de grabación ni
    /// mostrar "Unirse y tomar notas" en la tarjeta.
    var promptExcluded: Bool = false
    var eventIdentifier: String? = nil

    var hasParticipantsOrLink: Bool { !attendees.isEmpty || videoLink != nil }
}

extension CalendarMeeting {

    static let joinToleranceSeconds: TimeInterval = 300

    static func current(among meetings: [CalendarMeeting], at date: Date) -> CalendarMeeting? {
        meetings
            .filter {
                !$0.isAllDay
                    && date >= $0.start.addingTimeInterval(-joinToleranceSeconds)
                    && date < $0.end
            }
            .max { lhs, rhs in
                (lhs.attendees.isEmpty ? 0 : 1, lhs.start.timeIntervalSince1970)
                    < (rhs.attendees.isEmpty ? 0 : 1, rhs.start.timeIntervalSince1970)
            }
    }

    static func next(among meetings: [CalendarMeeting], at date: Date) -> CalendarMeeting? {
        meetings
            .filter { !$0.isAllDay && $0.end > date }
            .min { lhs, rhs in
                (lhs.start.timeIntervalSince1970, lhs.attendees.isEmpty ? 1 : 0)
                    < (rhs.start.timeIntervalSince1970, rhs.attendees.isEmpty ? 1 : 0)
            }
    }

    static func overlapping(among meetings: [CalendarMeeting], from windowStart: Date, to windowEnd: Date) -> CalendarMeeting? {
        meetings
            .filter { !$0.isAllDay && $0.start < windowEnd && $0.end > windowStart }
            .max { lhs, rhs in
                (lhs.attendees.isEmpty ? 0 : 1, overlapSeconds(of: lhs, from: windowStart, to: windowEnd))
                    < (rhs.attendees.isEmpty ? 0 : 1, overlapSeconds(of: rhs, from: windowStart, to: windowEnd))
            }
    }

    static func overlapSeconds(of meeting: CalendarMeeting, from windowStart: Date, to windowEnd: Date) -> TimeInterval {
        max(0, min(windowEnd, meeting.end).timeIntervalSince(max(windowStart, meeting.start)))
    }

    static func attendeeName(name: String?, address: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        if !trimmed.isEmpty, !trimmed.contains("@") {
            return trimmed
        }
        if let address, !address.isEmpty {
            return nameFromEmail(address)
        }
        return trimmed.isEmpty ? nil : nameFromEmail(trimmed)
    }

    static func nameFromEmail(_ address: String) -> String {
        let raw = address.hasPrefix("mailto:") ? String(address.dropFirst("mailto:".count)) : address
        let local = raw.split(separator: "@").first.map(String.init) ?? raw
        let words = local
            .split(whereSeparator: { "._-+".contains($0) })
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .filter { !$0.isEmpty && Int($0) == nil }
        return words.isEmpty ? raw : words.joined(separator: " ")
    }

    static func uniqueAttendees(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    static func wikilinked(_ names: [String]) -> [String] {
        names.map { "[[\($0)]]" }
    }

    static func participants(meeting: CalendarMeeting?, fallback: [String]) -> [String] {
        guard let meeting, !meeting.attendees.isEmpty else { return fallback }
        return wikilinked(meeting.attendees)
    }

    static let videoDomains = [
        "meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "discord.gg"
    ]

    static func videoLink(in texts: [String?]) -> String? {
        for text in texts {
            guard let text, !text.isEmpty else { continue }
            var rest = Substring(text)
            while let schemeRange = rest.range(of: "https://") ?? rest.range(of: "http://") {
                let candidate = rest[schemeRange.lowerBound...]
                    .prefix { !$0.isWhitespace && !"<>\"')".contains($0) }
                if videoDomains.contains(where: { candidate.contains($0) }) {
                    return String(candidate)
                }
                rest = rest[schemeRange.upperBound...]
            }
        }
        return nil
    }

    static func isIgnored(calendarTitle: String, ignored: [String]) -> Bool {
        ignored.contains(calendarTitle.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Prefijos de título que delatan una reunión cancelada cuando el status
    /// de EKEvent no alcanza a reflejarlo (algunas cuentas Exchange/CalDAV
    /// reescriben el título en vez de marcar `.canceled`).
    static let cancelledTitlePrefixes = ["cancelado:", "canceled:", "cancelled:", "cancelada:"]

    static func hasCancelledTitlePrefix(_ title: String) -> Bool {
        let folded = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
        return cancelledTitlePrefixes.contains { folded.hasPrefix($0) }
    }

    /// Lógica pura: una reunión se oculta en toda la app (agenda, tarjeta,
    /// título de barra, brief, decisión del aviso) si está cancelada
    /// (status de EKEvent o prefijo de título), si el usuario la rechazó,
    /// o si es un evento de todo-el-día.
    static func isHidden(title: String, isAllDay: Bool, statusCancelled: Bool, userDeclined: Bool) -> Bool {
        isAllDay || statusCancelled || userDeclined || hasCancelledTitlePrefix(title)
    }

    static func filtered(_ meetings: [CalendarMeeting], ignoreNoParticipants: Bool) -> [CalendarMeeting] {
        guard ignoreNoParticipants else { return meetings }
        return meetings.filter(\.hasParticipantsOrLink)
    }

    func countdown(at date: Date) -> String {
        let seconds = start.timeIntervalSince(date)
        guard seconds > 0 else { return "ahora" }
        let minutes = Int((seconds / 60).rounded(.up))
        guard minutes >= 60 else { return "en \(minutes) min" }
        let remainder = minutes % 60
        return remainder == 0 ? "en \(minutes / 60) h" : "en \(minutes / 60) h \(remainder) min"
    }

    func barCountdown(at date: Date) -> String? {
        let seconds = start.timeIntervalSince(date)
        guard seconds > 0, seconds <= 3_600 else { return nil }
        return "\(Int((seconds / 60).rounded(.up)))m"
    }
}

final class MeetingCalendar {

    static let shared = MeetingCalendar()

    private let store = EKEventStore()

    static var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    static var isAuthorized: Bool {
        CalendarAccessPolicy.hasFullAccess(authorizationStatus)
    }

    static var statusDescription: String {
        switch authorizationStatus {
        case .fullAccess: return "concedido"
        case .notDetermined: return "sin solicitar (corre: aria-capture calendar)"
        case .writeOnly: return "solo escritura — insuficiente"
        default: return "DENEGADO (Ajustes › Privacidad y seguridad › Calendarios)"
        }
    }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func meetings(from start: Date, to end: Date) -> [CalendarMeeting] {
        guard Self.isAuthorized, start < end else { return [] }
        let config = AriaConfig.load()
        let ignored = config.ignoredCalendars
        let excludedCalendars = config.promptExcludedCalendarIDs
        let includedCalendars = config.promptIncludedCalendarIDs
        let excludedAccounts = config.promptExcludedAccountIDs
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard let eventStart = event.startDate, let eventEnd = event.endDate else { return nil }
            if let calendarTitle = event.calendar?.title,
               CalendarMeeting.isIgnored(calendarTitle: calendarTitle, ignored: ignored) {
                return nil
            }
            let title = event.title?.trimmingCharacters(in: .whitespaces) ?? ""
            let userDeclined = (event.attendees ?? []).contains {
                $0.isCurrentUser && $0.participantStatus == .declined
            }
            if CalendarMeeting.isHidden(
                title: title,
                isAllDay: event.isAllDay,
                statusCancelled: event.status == .canceled,
                userDeclined: userDeclined
            ) {
                return nil
            }
            let participants = (event.attendees ?? []).filter {
                $0.participantType == .person || $0.participantType == .unknown
            }
            let names = participants.compactMap {
                CalendarMeeting.attendeeName(name: $0.name, address: $0.url.absoluteString)
            }
            let companies = participants.compactMap {
                PeopleNotes.company(fromAddress: $0.url.absoluteString)
            }
            let accountKind = CalendarAccountKind.classify(
                sourceType: event.calendar?.source?.sourceType ?? .local,
                sourceTitle: event.calendar?.source?.title ?? ""
            )
            let promptExcluded = CalendarPromptPolicy.isExcluded(
                calendarIdentifier: event.calendar?.calendarIdentifier ?? "",
                sourceIdentifier: event.calendar?.source?.sourceIdentifier ?? "",
                accountKind: accountKind,
                promptExcludedCalendars: excludedCalendars,
                promptIncludedCalendars: includedCalendars,
                promptExcludedAccounts: excludedAccounts
            )
            return CalendarMeeting(
                title: title.isEmpty ? "Reunión" : title,
                start: eventStart,
                end: eventEnd,
                attendees: CalendarMeeting.uniqueAttendees(names),
                isAllDay: event.isAllDay,
                companies: CalendarMeeting.uniqueAttendees(companies),
                videoLink: CalendarMeeting.videoLink(in: [event.location, event.notes, event.url?.absoluteString]),
                promptExcluded: promptExcluded,
                eventIdentifier: event.eventIdentifier
            )
        }
    }

    func relevantMeetings(from start: Date, to end: Date) -> [CalendarMeeting] {
        CalendarMeeting.filtered(
            meetings(from: start, to: end),
            ignoreNoParticipants: AriaConfig.load().ignoreNoParticipants
        )
    }

    func currentMeeting(at date: Date = Date()) -> CalendarMeeting? {
        CalendarMeeting.current(
            among: relevantMeetings(from: date.addingTimeInterval(-1), to: date.addingTimeInterval(CalendarMeeting.joinToleranceSeconds)),
            at: date
        )
    }

    /// Fila de la sección "Calendarios" de Ajustes: un calendario de una cuenta,
    /// con el estado resuelto de sus dos toggles ("Mostrar en agenda" = !ignored,
    /// "Ofrecer grabar" = !promptExcluded).
    struct CalendarListing: Identifiable, Equatable {
        let id: String
        let sourceID: String
        let source: String
        let title: String
        let ignored: Bool
        let promptExcluded: Bool
        let accountKind: CalendarAccountKind
    }

    func calendarListings() -> [CalendarListing] {
        guard Self.isAuthorized else { return [] }
        let config = AriaConfig.load()
        let ignored = config.ignoredCalendars
        let excludedCalendars = config.promptExcludedCalendarIDs
        let includedCalendars = config.promptIncludedCalendarIDs
        let excludedAccounts = config.promptExcludedAccountIDs
        return store.calendars(for: .event)
            .map { calendar in
                let accountKind = CalendarAccountKind.classify(
                    sourceType: calendar.source?.sourceType ?? .local,
                    sourceTitle: calendar.source?.title ?? ""
                )
                return CalendarListing(
                    id: calendar.calendarIdentifier,
                    sourceID: calendar.source?.sourceIdentifier ?? "",
                    source: calendar.source?.title ?? "(sin cuenta)",
                    title: calendar.title,
                    ignored: CalendarMeeting.isIgnored(calendarTitle: calendar.title, ignored: ignored),
                    promptExcluded: CalendarPromptPolicy.isExcluded(
                        calendarIdentifier: calendar.calendarIdentifier,
                        sourceIdentifier: calendar.source?.sourceIdentifier ?? "",
                        accountKind: accountKind,
                        promptExcludedCalendars: excludedCalendars,
                        promptIncludedCalendars: includedCalendars,
                        promptExcludedAccounts: excludedAccounts
                    ),
                    accountKind: accountKind
                )
            }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    func nextMeeting(within seconds: TimeInterval = 12 * 3_600, at date: Date = Date()) -> CalendarMeeting? {
        CalendarMeeting.next(among: relevantMeetings(from: date, to: date.addingTimeInterval(seconds)), at: date)
    }

    func meeting(overlapping windowStart: Date, to windowEnd: Date) -> CalendarMeeting? {
        CalendarMeeting.overlapping(
            among: relevantMeetings(from: windowStart, to: windowEnd),
            from: windowStart,
            to: windowEnd
        )
    }
}
