import Foundation

struct EnhancedNote {
    let title: String
    let markdown: String
    let inputTokens: Int
    let outputTokens: Int
}

final class MeetingEnhancer {

    static let systemPrompt = """
    Eres el asistente de notas de reuniones "NotarIA". Recibes el transcript diarizado de una
    reunión y las notas sueltas del usuario. Produce una nota en Markdown en español con esta
    estructura EXACTA (omite secciones vacías):

    # <título breve y descriptivo>
    > Fecha · Participantes · Duración

    ## Resumen
    <3–6 líneas>

    ## Decisiones
    - <decisión> (quién / contexto)

    ## Action items
    - [ ] <acción> — responsable — fecha si se dijo

    ## Preguntas abiertas / riesgos
    - <...>

    ## Citas clave
    > "<cita textual relevante>" — hablante

    Reglas: no inventes; si algo no está claro, márcalo. Las notas del usuario (si las hay) son
    la ESTRUCTURA y el foco de la nota: respeta su orden e intención. El transcript sirve para
    EXPANDIR esos puntos con detalle, cifras, citas y matices — nunca para reemplazar o
    reordenar lo que el usuario ya escribió. Usa wikilinks [[Nombre]] para personas/proyectos
    si aparecen. Responde SOLO con la nota en Markdown, sin preámbulos ni cierres.

    Hablantes: "Yo" es el usuario (micrófono). El resto puede venir ya separado en "Hablante 1",
    "Hablante 2", etc. (voces distintas detectadas dentro del canal del sistema) o sin separar como
    "Otros"/"Ellos" si no se pudo distinguir. Una etiqueta puede traer una sugerencia de nombre sin
    confirmar, con el formato "Hablante N (¿Ana?)": trátala como DUDOSA, no como un hecho — puedes
    usarla para dar contexto ("probablemente Ana") pero NUNCA la presentes como certeza ni le
    atribuyas una decisión o action item igual que a un nombre confirmado. Cuando una etiqueta ya
    es un nombre real sin paréntesis (p.ej. "Ana" o "Ana"), eso SÍ está confirmado (por
    calendario, memoria de voz o el usuario) y puedes usarlo con naturalidad al citar y al asignar
    decisiones y action items. Si solo tienes "Hablante N"/"Otros" sin ninguna pista, conserva esa
    etiqueta — NUNCA inventes nombres ni resuelvas un "(¿Nombre?)" a secas sin el signo de duda.

    Contexto visual: si recibes un bloque "Contexto visual (OCR local)", es texto extraído por OCR
    de capturas de pantalla durante la reunión, con hora. Úsalo solo para enriquecer con detalle
    (cifras, títulos de diapositivas, URLs, nombres en pantalla) lo que ya dicen las notas o el
    transcript — nunca como fuente única de una decisión o action item, y nunca lo inventes si no
    viene en el mensaje.
    """

    private let client: EnhanceBackend
    private let activeSystemPrompt: String

    init(client: EnhanceBackend, template: Recipe? = nil) {
        self.client = client
        let config = AriaConfig.load()
        activeSystemPrompt = Self.composedSystemPrompt(
            base: config.resolvedSystemPrompt ?? Self.systemPrompt,
            language: config.language,
            template: template
        )
    }

    static func languageInstruction(_ language: String) -> String? {
        switch language {
        case "en":
            return "Idioma: escribe TODA la nota en inglés (títulos y secciones incluidos), aunque estas instrucciones estén en español."
        case "auto":
            return "Idioma: escribe la nota en el idioma predominante de la reunión según el transcript."
        default:
            return nil
        }
    }

    static func composedSystemPrompt(base: String, language: String = "es", template: Recipe?) -> String {
        var prompt = base
        if let instruction = languageInstruction(language) {
            prompt += "\n\n" + instruction
        }
        if let template {
            prompt += "\n\n## Plantilla \"\(template.name)\" — enfoque de esta reunión\n" + template.prompt
        }
        return prompt
    }

    static func composeUserMessage(
        transcript: String,
        notes: String,
        date: Date,
        durationSeconds: TimeInterval,
        calendarMeeting: CalendarMeeting? = nil,
        visualContext: String? = nil
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "es_CO")
        dateFormatter.dateFormat = "EEEE d 'de' MMMM 'de' yyyy, HH:mm"
        let minutes = Int(durationSeconds) / 60

        var message = """
        Fecha de la reunión: \(dateFormatter.string(from: date))
        Duración: \(minutes) min
        """
        if let meeting = calendarMeeting {
            message += "\nTítulo en el calendario: \(meeting.title)"
            if !meeting.attendees.isEmpty {
                message += "\nParticipantes según el calendario: \(meeting.attendees.joined(separator: ", "))"
                message += "\n(Usa estos nombres reales al atribuir hablantes y en los wikilinks.)"
            }
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            message += "\n\n## Notas del usuario (estructura a respetar)\n\(trimmedNotes)"
        }
        if let visualContext, !visualContext.isEmpty {
            message += "\n\n## Contexto visual (OCR local, por hora)\n\(visualContext)"
        }
        message += """


        ## Transcript diarizado (para expandir y completar los puntos anteriores)
        \(transcript.isEmpty ? "(sin voz detectada)" : transcript)
        """
        return message
    }

    func enhance(
        transcript: String,
        notes: String,
        date: Date,
        durationSeconds: TimeInterval,
        calendarMeeting: CalendarMeeting? = nil,
        visualContext: String? = nil,
        onText: ((String) -> Void)? = nil
    ) async throws -> EnhancedNote {
        let message = Self.composeUserMessage(
            transcript: transcript,
            notes: notes,
            date: date,
            durationSeconds: durationSeconds,
            calendarMeeting: calendarMeeting,
            visualContext: visualContext
        )

        let result = try await client.complete(
            system: activeSystemPrompt,
            userMessage: message,
            maxTokens: 16_000,
            onText: onText
        )
        let markdown = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return EnhancedNote(
            title: Self.extractTitle(from: markdown) ?? "Reunion sin titulo",
            markdown: markdown,
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens
        )
    }

    static func extractTitle(from markdown: String) -> String? {
        for line in markdown.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
