import Foundation

struct SpeakerResolution {
    let segments: [TranscriptSegment]
    let assignments: [String: SpeakerAssignment]
    /// Embeddings re-indexados por la etiqueta FINAL ya aplicada en `segments` (p.ej.
    /// "Hablante 2 (¿Ana?)" o "Ana"), listos para guardarse junto con la reunión.
    let embeddings: [String: SpeakerEmbedding]
}

/// Punto único de integración de las capas 1+2 usado tanto por `main.swift` (CLI `enhance`) como
/// por `MenuBarApp.swift` (`stopAndGenerate`), para no duplicar la lógica de naming en los dos
/// sitios donde se genera la nota final.
enum SpeakerResolutionPipeline {

    static func resolve(
        segments: [TranscriptSegment],
        calendarMeeting: CalendarMeeting?,
        speakerEmbeddings: [String: SpeakerEmbedding],
        voiceMemoryEnabled: Bool
    ) -> SpeakerResolution {
        let labels = SpeakerNaming.orderedSpeakerLabels(in: segments)

        var voiceMemoryMatches: [String: (name: String, confidence: Double)] = [:]
        if voiceMemoryEnabled, !speakerEmbeddings.isEmpty, let store = try? VoiceMemoryStore() {
            let profiles = store.load()
            for (label, embedding) in speakerEmbeddings {
                if let match = VoiceMemoryStore.bestMatch(embedding, in: profiles) {
                    voiceMemoryMatches[label] = match
                }
            }
        }

        let assignments = SpeakerNaming.resolve(
            speakerLabels: labels,
            segments: segments,
            calendarAttendees: calendarMeeting?.attendees ?? [],
            voiceMemoryMatches: voiceMemoryMatches
        )
        let renamed = SpeakerNaming.applyAssignments(to: segments, assignments: assignments)

        var relabeledEmbeddings: [String: SpeakerEmbedding] = [:]
        for (originalLabel, embedding) in speakerEmbeddings {
            let finalLabel = assignments[originalLabel]?.displayLabel(for: originalLabel) ?? originalLabel
            relabeledEmbeddings[finalLabel] = embedding
        }

        return SpeakerResolution(segments: renamed, assignments: assignments, embeddings: relabeledEmbeddings)
    }
}
