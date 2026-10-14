import Foundation

struct MeetingNote {
    var title: String
    var date: Date
    var participants: [String]
    var durationSeconds: TimeInterval
    var body: String
    var transcript: String?
    var companies: [String] = []
    var source: String = "aria"
    var externalID: String? = nil
    var url: String? = nil
    var pauses: [PauseInterval] = []
}

final class ObsidianWriter {

    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? AriaConfig.load().resolvedObsidianDir
    }

    @discardableResult
    func write(_ note: MeetingNote, overwriting existingPath: URL? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let day = dayFormatter.string(from: note.date)

        let fileURL: URL
        if let existingPath, FileManager.default.fileExists(atPath: existingPath.path) {
            fileURL = existingPath
        } else {
            let baseName = "\(day) - \(Self.sanitized(note.title))"
            var candidate = directory.appendingPathComponent("\(baseName).md")
            var attempt = 2
            while FileManager.default.fileExists(atPath: candidate.path) {
                candidate = directory.appendingPathComponent("\(baseName) (\(attempt)).md")
                attempt += 1
            }
            fileURL = candidate
        }

        try render(note, day: day).write(to: fileURL, atomically: true, encoding: .utf8)
        try? PeopleNotes.ensureStubs(
            people: note.participants.compactMap(PeopleNotes.personName(fromWikilink:)),
            companies: note.companies,
            notesDirectory: directory,
            date: note.date
        )
        return fileURL
    }

    private func render(_ note: MeetingNote, day: String) -> String {
        let participantsYAML = note.participants.isEmpty
            ? "[]"
            : "[" + note.participants.map(Self.yamlQuoted).joined(separator: ", ") + "]"
        let minutes = Int(note.durationSeconds) / 60
        let seconds = Int(note.durationSeconds) % 60

        let companiesLine = note.companies.isEmpty
            ? ""
            : "\nempresas: [" + CalendarMeeting.wikilinked(note.companies).map(Self.yamlQuoted).joined(separator: ", ") + "]"
        var externalLines = ""
        if let externalID = note.externalID {
            externalLines = "\ngranola_id: \(Self.yamlQuoted(externalID))"
            if let url = note.url, !url.isEmpty {
                externalLines += "\nurl: \(Self.yamlQuoted(url))"
            }
        }
        let pausasLine = note.pauses.isEmpty
            ? ""
            : "\npausas: [" + note.pauses.map { Self.yamlQuoted(PauseLogic.rangeLabel(for: $0)) }.joined(separator: ", ") + "]"
        var output = """
        ---
        titulo: \(Self.yamlQuoted(note.title))
        tipo: reunion
        creado: \(day)
        fuente: \(note.source)
        participantes: \(participantsYAML)\(companiesLine)\(externalLines)
        duracion: \(String(format: "%02d:%02d", minutes, seconds))\(pausasLine)
        tags: [reunion, \(note.source)]
        ---

        \(note.body.trimmingCharacters(in: .whitespacesAndNewlines))
        """

        if let transcript = note.transcript, !transcript.isEmpty {
            let quoted = transcript
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> \($0)" }
                .joined(separator: "\n")
            output += """


            > [!note]- Transcript
            \(quoted)
            """
        }
        return output + "\n"
    }

    static func yamlQuoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func sanitized(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
        let cleaned = title.components(separatedBy: forbidden).joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let capped = String(cleaned.prefix(80)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? "Reunion sin titulo" : capped
    }
}
