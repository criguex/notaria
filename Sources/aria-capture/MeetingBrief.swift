import Foundation

struct PastMeetingRef {
    let record: MeetingRecord
    let participants: [String]
}

enum MeetingBrief {

    static let systemPrompt = """
    Eres Aria, asistente de notas de reuniones. Vas a preparar un BRIEF PRE-REUNIÓN corto para
    el usuario ("Yo" en los transcripts) a partir de sus reuniones previas con las mismas
    personas. Estructura:

    ## Brief: <título de la reunión que viene>
    - **Última vez** (fecha): 1-2 líneas de dónde quedó la conversación.
    - **Pendientes abiertos**: action items no resueltos, con responsable (los del usuario primero).
    - **Acuerdos vigentes**: decisiones que siguen aplicando.
    - **Para retomar**: preguntas abiertas o temas que quedaron en el aire.

    Solo usa lo que esté en el contexto, con fechas; si una sección queda vacía, omítela.
    Máximo ~15 líneas. Responde SOLO con el brief en Markdown.
    """

    static func participants(fromNote content: String) -> [String] {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("participantes:") else { continue }
            var names: [String] = []
            var rest = Substring(line.dropFirst("participantes:".count))
            while let open = rest.firstIndex(of: "\"") {
                rest = rest[rest.index(after: open)...]
                guard let close = rest.firstIndex(of: "\"") else { break }
                let raw = String(rest[..<close])
                if !raw.isEmpty { names.append(raw) }
                rest = rest[rest.index(after: close)...]
            }
            return names
        }
        return []
    }

    static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    static func score(participants: [String], attendees: [String], pastTitle: String, title: String) -> Int {
        let normalizedAttendees = Set(attendees.map(normalized).filter { !$0.isEmpty })
        let overlap = participants.map(normalized).filter { normalizedAttendees.contains($0) }.count
        let currentTitle = title.trimmingCharacters(in: .whitespaces).lowercased()
        let previousTitle = pastTitle.trimmingCharacters(in: .whitespaces).lowercased()
        let titleBonus = !currentTitle.isEmpty && !previousTitle.isEmpty
            && (currentTitle == previousTitle || currentTitle.contains(previousTitle) || previousTitle.contains(currentTitle))
            ? 1 : 0
        return overlap * 2 + titleBonus
    }

    static func relevant(past: [PastMeetingRef], attendees: [String], title: String, limit: Int = 3) -> [PastMeetingRef] {
        past
            .map { (ref: $0, score: score(participants: $0.participants, attendees: attendees, pastTitle: $0.record.title, title: title)) }
            .filter { $0.score > 0 }
            .sorted {
                ($0.score, $0.ref.record.date.timeIntervalSince1970)
                    > ($1.score, $1.ref.record.date.timeIntervalSince1970)
            }
            .prefix(limit)
            .map(\.ref)
    }

    static func generate(
        attendees: [String],
        title: String,
        onText: ((String) -> Void)? = nil
    ) async throws -> ChatAnswer {
        let store = try MeetingStore()
        let past = try store.recentMeetings(limit: 100).map { record in
            PastMeetingRef(
                record: record,
                participants: (try? String(contentsOf: URL(fileURLWithPath: record.notePath), encoding: .utf8))
                    .map(Self.participants(fromNote:)) ?? []
            )
        }
        let selected = relevant(past: past, attendees: attendees, title: title)
        guard !selected.isEmpty else {
            throw NSError(domain: "aria.brief", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No hay reuniones previas con estos participantes o título en el historial."
            ])
        }
        let contexts = try selected.map { ref in
            ChatMeetingContext(
                record: ref.record,
                transcript: TranscriptFormatter.render(try store.segments(meetingID: ref.record.id)),
                notes: try store.quickNotes(meetingID: ref.record.id)
            )
        }
        let rendered = MeetingChat.renderContext(contexts)
        let people = attendees.isEmpty ? "(sin lista de asistentes)" : attendees.joined(separator: ", ")
        let message = """
        ## Reunión que viene
        Título: \(title.isEmpty ? "(sin título)" : title)
        Asistentes: \(people)

        ## Contexto de reuniones previas con estas personas
        \(rendered.text)
        """
        return try await MeetingChat.complete(
            system: systemPrompt,
            message: message,
            rendered: rendered,
            onText: onText
        )
    }
}
