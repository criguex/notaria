import Foundation

enum SpeakerMap {

    static func parse(_ raw: String) throws -> [String: String] {
        var map: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                throw Self.error("Par inválido '\(pair.trimmingCharacters(in: .whitespaces))'. Formato: \"Otros=Juan,Yo=Ana\".")
            }
            let label = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let name = parts[1].trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, !name.isEmpty else {
                throw Self.error("Par inválido '\(pair.trimmingCharacters(in: .whitespaces))': ni la etiqueta ni el nombre pueden estar vacíos.")
            }
            guard map[label] == nil else {
                throw Self.error("Etiqueta repetida '\(parts[0].trimmingCharacters(in: .whitespaces))'.")
            }
            map[label] = name
        }
        guard !map.isEmpty else {
            throw Self.error("Mapa de hablantes vacío. Formato: \"Otros=Juan,Yo=Ana\".")
        }
        return map
    }

    static func apply(_ map: [String: String], to segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.map { segment in
            guard let name = map[segment.speaker.lowercased()] else { return segment }
            return TranscriptSegment(start: segment.start, end: segment.end, text: segment.text, speaker: name)
        }
    }

    static func apply(_ map: [String: String], to speakers: [String]) -> [String] {
        speakers.map { map[$0.lowercased()] ?? $0 }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "aria.speakers", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
