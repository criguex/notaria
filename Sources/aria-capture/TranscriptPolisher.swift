import Foundation

enum TranscriptPolisher {

    static let systemPrompt = """
    Eres un corrector de transcripts de reuniones generados por whisper. Recibes un transcript
    diarizado con líneas "[MM:SS] Hablante: texto" y devuelves EXACTAMENTE el mismo transcript
    corregido: puntuación, mayúsculas, errores evidentes de transcripción (palabras mal oídas,
    corregibles por contexto), términos técnicos y nombres propios (usa los participantes del
    calendario si se listan). Reglas DURAS: mismo número de líneas, mismos timestamps y mismos
    hablantes; prohibido añadir, quitar, reordenar o resumir contenido; si dudas de una palabra,
    déjala tal cual. Responde SOLO con el transcript corregido, sin preámbulos ni cierres.
    """

    static func message(transcript: String, meeting: CalendarMeeting?) -> String {
        var message = ""
        if let meeting, !meeting.attendees.isEmpty {
            message += "Participantes según el calendario: \(meeting.attendees.joined(separator: ", "))\n\n"
        }
        message += "## Transcript a corregir\n" + transcript
        return message
    }

    static func parsedTexts(from output: String, expectedCount: Int) -> [String]? {
        let texts = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line -> String? in
                guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
                let rest = line[line.index(after: close)...]
                guard let colon = rest.firstIndex(of: ":") else { return nil }
                return String(rest[rest.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        return texts.count == expectedCount ? texts : nil
    }

    static func applied(texts: [String], to segments: [TranscriptSegment]) -> [TranscriptSegment] {
        zip(segments, texts).map { segment, text in
            TranscriptSegment(start: segment.start, end: segment.end, text: text, speaker: segment.speaker)
        }
    }

    static func polish(
        segments: [TranscriptSegment],
        calendarMeeting: CalendarMeeting?,
        client: EnhanceBackend,
        onText: ((String) -> Void)? = nil
    ) async throws -> [TranscriptSegment] {
        guard !segments.isEmpty else { return segments }
        let result = try await client.complete(
            system: systemPrompt,
            userMessage: message(transcript: TranscriptFormatter.render(segments), meeting: calendarMeeting),
            maxTokens: 16_000,
            onText: onText
        )
        guard let texts = parsedTexts(from: result.text, expectedCount: segments.count) else {
            throw NSError(domain: "aria.polish", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "El pulido no devolvió el mismo número de líneas — se conserva el transcript de whisper."
            ])
        }
        return applied(texts: texts, to: segments)
    }
}
