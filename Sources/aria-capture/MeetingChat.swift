import Foundation

struct ChatMeetingContext {
    let record: MeetingRecord
    let transcript: String
    let notes: [QuickNote]
}

struct ChatAnswer {
    let text: String
    let meetingsIncluded: Int
    let meetingsOmitted: Int
    let backendName: String
    let inputTokens: Int
    let outputTokens: Int
}

enum MeetingChat {

    static let defaultContextBudget = 60_000
    static let maxTranscriptChars = 20_000

    static let systemPrompt = """
    Eres Aria, la memoria de reuniones del usuario. Recibes el contexto de sus reuniones
    (transcripts diarizados donde "Yo" es el usuario y "Otros" son los demás, más sus notas)
    y una pregunta. Responde SOLO con base en ese contexto y cita la reunión (fecha y título)
    que respalda cada afirmación. Si la respuesta no aparece en las reuniones, dilo claramente
    sin inventar. Responde en español, conciso y accionable.
    """

    static func renderMeeting(_ meeting: ChatMeetingContext) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let minutes = Int(meeting.record.durationSeconds) / 60
        var block = "### Reunión \(formatter.string(from: meeting.record.date)) — \(meeting.record.title) (\(minutes) min)\n"
        if !meeting.notes.isEmpty {
            block += "Notas del usuario:\n"
            for note in meeting.notes {
                block += note.timestamp.isEmpty ? "- \(note.text)\n" : "- [\(note.timestamp)] \(note.text)\n"
            }
        }
        if meeting.transcript.isEmpty {
            block += "Transcript: (sin voz detectada)\n"
        } else if meeting.transcript.count > maxTranscriptChars {
            block += "Transcript:\n\(meeting.transcript.prefix(maxTranscriptChars))\n… (transcript recortado)\n"
        } else {
            block += "Transcript:\n\(meeting.transcript)\n"
        }
        return block
    }

    static func renderContext(
        _ meetingsMostRecentFirst: [ChatMeetingContext],
        budget: Int = defaultContextBudget
    ) -> (text: String, included: Int, omitted: Int) {
        var blocks: [String] = []
        var used = 0
        var omitted = 0
        for meeting in meetingsMostRecentFirst {
            let block = renderMeeting(meeting)
            if !blocks.isEmpty, used + block.count > budget {
                omitted += 1
                continue
            }
            used += block.count
            blocks.append(block)
        }
        return (blocks.reversed().joined(separator: "\n"), blocks.count, omitted)
    }

    static func userMessage(question: String, context: String) -> String {
        """
        ## Contexto de reuniones
        \(context)

        ## Pregunta
        \(question)
        """
    }

    static let recipeSystemPrompt = """
    Eres Aria, asistente de notas de reuniones. Recibes el contexto de reuniones del usuario
    (transcripts diarizados donde "Yo" es el usuario y "Otros" son los demás, más sus notas)
    y una instrucción (recipe). Aplica la instrucción sobre ese contexto sin inventar datos
    que no estén en él. Responde SOLO con el entregable pedido, listo para usar tal cual,
    sin preámbulos ni cierres.
    """

    static func recipeMessage(recipe: Recipe, context: String) -> String {
        """
        ## Contexto de reuniones
        \(context)

        ## Recipe: \(recipe.name)
        \(recipe.prompt)
        """
    }

    static func gatherContexts(meetingID: Int64?, limit: Int) throws -> [ChatMeetingContext] {
        let store = try MeetingStore()
        let records: [MeetingRecord]
        if let meetingID {
            guard let record = try store.recentMeetings(limit: 1_000).first(where: { $0.id == meetingID }) else {
                throw Self.error("No existe la reunión [\(meetingID)] en el historial (revisa: aria-capture history).")
            }
            records = [record]
        } else {
            records = try store.recentMeetings(limit: limit)
        }
        guard !records.isEmpty else {
            throw Self.error("Sin reuniones en el historial todavía. Graba una primero (aria-capture menubar).")
        }
        return try records.map { record in
            ChatMeetingContext(
                record: record,
                transcript: TranscriptFormatter.render(try store.segments(meetingID: record.id)),
                notes: try store.quickNotes(meetingID: record.id)
            )
        }
    }

    static func complete(
        system: String,
        message: String,
        rendered: (text: String, included: Int, omitted: Int),
        onText: ((String) -> Void)?
    ) async throws -> ChatAnswer {
        guard let backend = ClaudeCLIClient.preferredBackend() else {
            throw Self.error("Sin backend disponible: ni API key en Keychain ni CLI de Claude Code instalado.")
        }
        let result = try await backend.complete(
            system: system,
            userMessage: message,
            maxTokens: 8_000,
            onText: onText
        )
        return ChatAnswer(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            meetingsIncluded: rendered.included,
            meetingsOmitted: rendered.omitted,
            backendName: backend.backendName,
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens
        )
    }

    static func answer(
        question: String,
        meetingID: Int64? = nil,
        limit: Int = 10,
        onText: ((String) -> Void)? = nil
    ) async throws -> ChatAnswer {
        let rendered = renderContext(try gatherContexts(meetingID: meetingID, limit: limit))
        return try await complete(
            system: systemPrompt,
            message: userMessage(question: question, context: rendered.text),
            rendered: rendered,
            onText: onText
        )
    }

    static func applyRecipe(
        _ recipe: Recipe,
        meetingID: Int64? = nil,
        limit: Int = 1,
        onText: ((String) -> Void)? = nil
    ) async throws -> ChatAnswer {
        let rendered = renderContext(try gatherContexts(meetingID: meetingID, limit: limit))
        return try await complete(
            system: recipeSystemPrompt,
            message: recipeMessage(recipe: recipe, context: rendered.text),
            rendered: rendered,
            onText: onText
        )
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "aria.chat", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
