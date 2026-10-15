import Foundation

struct SpeakerAssignment: Equatable {
    enum Source: Equatable {
        case voiceMemory
        case mentionedAndAttendee
        case mentioned
        case calendarOrder
    }

    var name: String
    var confidence: Double
    var source: Source

    /// >= este umbral, el nombre se usa directo (sin "¿?") en segmentos/nota.
    static let highConfidence = 0.7
    /// por debajo de este umbral no se sugiere nada (demasiado débil para mostrar).
    static let minConfidence = 0.3

    func displayLabel(for originalLabel: String) -> String {
        guard confidence >= Self.minConfidence else { return originalLabel }
        if confidence >= Self.highConfidence {
            return name
        }
        return "\(originalLabel) (¿\(name)?)"
    }
}

/// Capa 2: ponerle nombre a "Hablante N". Combina asistentes del calendario, nombres dichos en la
/// conversación ("gracias, Ana") y (opcional) memoria de voz — ver `VoiceMemoryStore.swift`.
/// Todo puro y testeable salvo la lectura de memoria de voz, que vive aparte.
enum SpeakerNaming {

    /// Etiquetas de hablante (no "Yo"/mic) en orden de primera aparición en el transcript.
    static func orderedSpeakerLabels(in segments: [TranscriptSegment], excluding micLabel: String = "Yo") -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for segment in segments where segment.speaker != micLabel {
            if seen.insert(segment.speaker).inserted {
                ordered.append(segment.speaker)
            }
        }
        return ordered
    }

    static func speakingSeconds(in segments: [TranscriptSegment]) -> [String: Double] {
        var totals: [String: Double] = [:]
        for segment in segments {
            totals[segment.speaker, default: 0] += max(0, segment.end - segment.start)
        }
        return totals
    }

    private static let vocativeLeadIns: Set<String> = [
        "gracias", "oye", "bueno", "listo", "perfecto", "vale", "ok", "okay", "claro", "a ver", "mira"
    ]

    private static let sentenceStartStopwords: Set<String> = [
        "bueno", "entonces", "pero", "claro", "sí", "no", "hola", "ok", "vale", "perfecto",
        "bien", "ahora", "mira", "oye", "eso", "esto", "yo", "nosotros", "ustedes", "ella", "él",
        "buenas", "buena", "perdón", "chao", "chau", "genial", "dale", "listo"
    ]

    /// Nombres propios mencionados en un texto: patrón vocativo ("gracias, Ana" / "oye Juan") o
    /// nombre al inicio de frase seguido de coma ("Ana, ¿qué opinas?"), filtrando stopwords.
    ///
    /// Se conserva el token SIN recortar (`rawTokens`) junto al recortado (`words`): recortar la
    /// puntuación antes de mirarla (como hacía la versión anterior) deja "seguido de coma" y
    /// "después de punto" siempre en falso, así que CUALQUIER primera palabra de cualquier turno
    /// ("Buenas", "Dale", "Perdón"...) se contaba como nombre — en una reunión de varias personas
    /// eso inunda el conteo de menciones con ruido y termina eligiendo mal (o de forma no
    /// determinística, por el orden de iteración del diccionario) entre dos hablantes reales.
    static func extractMentionedNames(from text: String) -> [String] {
        mentionedNamesWithPattern(in: text).map(\.name)
    }

    struct MentionedName {
        let name: String
        /// true: patrón vocativo ("gracias, Ana") — se dirige a quien YA habló (se le agradece/
        /// responde) → el hablante ANTERIOR. false: nombre al inicio de frase seguido de coma
        /// ("Ana, ¿qué opinas?") — se le da el turno a quien va a hablar → el hablante SIGUIENTE.
        let isVocative: Bool
    }

    private static func mentionedNamesWithPattern(in text: String) -> [MentionedName] {
        guard !text.isEmpty else { return [] }
        var found: [MentionedName] = []
        let rawTokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let words = rawTokens.map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces)) }

        for (i, word) in words.enumerated() {
            guard !word.isEmpty, isCapitalizedName(word) else { continue }
            let lowered = word.lowercased()
            guard !vocativeLeadIns.contains(lowered), !sentenceStartStopwords.contains(lowered) else { continue }
            if i > 0, vocativeLeadIns.contains(words[i - 1].lowercased()) {
                found.append(MentionedName(name: word, isVocative: true))
                continue
            }
            if i == 0 || isSentenceBoundary(rawTokens[i - 1]) {
                if rawTokens[i].hasSuffix(",") { found.append(MentionedName(name: word, isVocative: false)) }
            }
        }
        return found
    }

    private static func isCapitalizedName(_ word: String) -> Bool {
        guard let first = word.first, word.count >= 2, word.count <= 20 else { return false }
        guard first.isUppercase else { return false }
        return word.dropFirst().allSatisfy { $0.isLowercase || $0 == "-" }
    }

    private static func isSentenceBoundary(_ previousWord: String) -> Bool {
        previousWord.hasSuffix(".") || previousWord.hasSuffix("!") || previousWord.hasSuffix("?")
    }

    /// Para cada mención encontrada en un turno, se atribuye al hablante ADYACENTE distinto (el
    /// que responde o al que se dirige), no al que la pronuncia. Cuando los dos lados son
    /// hablantes DISTINTOS (p.ej. "Yo" moderando entre dos personas en una reunión de 3+), el
    /// patrón de la mención decide el lado correcto en vez de mezclar el nombre con los dos:
    /// vocativo ("gracias, Ana") → el hablante ANTERIOR; inicio de frase ("Ana, ¿qué opinas?")
    /// → el hablante SIGUIENTE.
    static func attributedMentions(in segments: [TranscriptSegment]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for i in segments.indices {
            let mentions = mentionedNamesWithPattern(in: segments[i].text)
            guard !mentions.isEmpty else { continue }
            let next = (i + 1 < segments.count && segments[i + 1].speaker != segments[i].speaker) ? segments[i + 1].speaker : nil
            let previous = (i > 0 && segments[i - 1].speaker != segments[i].speaker) ? segments[i - 1].speaker : nil

            for mention in mentions {
                let candidates: [String]
                if let next, let previous, next != previous {
                    candidates = [mention.isVocative ? previous : next]
                } else {
                    candidates = [next, previous].compactMap { $0 }
                }
                for candidate in candidates {
                    result[candidate, default: []].append(mention.name)
                }
            }
        }
        return result
    }

    private static func mostFrequent(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    /// Resuelve una sugerencia de nombre + confianza por cada etiqueta de hablante.
    static func resolve(
        speakerLabels: [String],
        segments: [TranscriptSegment],
        calendarAttendees: [String],
        voiceMemoryMatches: [String: (name: String, confidence: Double)] = [:]
    ) -> [String: SpeakerAssignment] {
        var assignments: [String: SpeakerAssignment] = [:]
        let mentions = attributedMentions(in: segments)
        let attendeeTokens = Set(calendarAttendees.flatMap { $0.split(separator: " ").map { String($0).lowercased() } })

        for (orderIndex, label) in speakerLabels.enumerated() {
            if let match = voiceMemoryMatches[label] {
                assignments[label] = SpeakerAssignment(name: match.name, confidence: max(match.confidence, SpeakerAssignment.highConfidence), source: .voiceMemory)
                continue
            }
            if let mentioned = mentions[label], let best = mostFrequent(mentioned) {
                if attendeeTokens.contains(best.lowercased()) {
                    assignments[label] = SpeakerAssignment(name: best, confidence: 0.85, source: .mentionedAndAttendee)
                } else {
                    assignments[label] = SpeakerAssignment(name: best, confidence: 0.4, source: .mentioned)
                }
                continue
            }
            if calendarAttendees.count == speakerLabels.count, orderIndex < calendarAttendees.count {
                assignments[label] = SpeakerAssignment(name: calendarAttendees[orderIndex], confidence: 0.35, source: .calendarOrder)
            }
        }
        return assignments
    }

    static func applyAssignments(to segments: [TranscriptSegment], assignments: [String: SpeakerAssignment]) -> [TranscriptSegment] {
        guard !assignments.isEmpty else { return segments }
        return segments.map { segment in
            guard let assignment = assignments[segment.speaker] else { return segment }
            var updated = segment
            updated.speaker = assignment.displayLabel(for: segment.speaker)
            return updated
        }
    }

    /// "Hablante 2 (¿Ana?)" -> ("Hablante 2", "Ana"); nil si la etiqueta no tiene esa forma.
    static func pendingConfirmation(in label: String) -> (base: String, suggestedName: String)? {
        guard let openParen = label.range(of: " (¿"), label.hasSuffix("?)") else { return nil }
        let base = String(label[label.startIndex..<openParen.lowerBound])
        let nameStart = openParen.upperBound
        let nameEnd = label.index(label.endIndex, offsetBy: -2)
        guard nameStart < nameEnd else { return nil }
        return (base, String(label[nameStart..<nameEnd]))
    }

    /// Etiqueta limpia para usos donde "(¿Nombre?)" no tiene sentido (p.ej. frontmatter/wikilinks).
    static func cleanLabel(_ label: String) -> String {
        pendingConfirmation(in: label)?.base ?? label
    }
}
