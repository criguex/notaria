import Foundation

struct GranolaExportRecord: Codable {
    let source: String
    let id: String
    let title: String
    let meeting_at: String
    let created_at: String?
    let updated_at: String?
    let url: String?
    let participants: [String]
    let summary_markdown: String
    let transcript: String?
    let transcript_unavailable: Bool?
}

enum GranolaImportError: LocalizedError {
    case notADirectory(String)

    var errorDescription: String? {
        switch self {
        case .notADirectory(let path):
            return "No es un directorio: \(path)"
        }
    }
}

struct GranolaImportResult {
    var imported = 0
    var updated = 0
    var failed: [(file: String, error: String)] = []
}

enum GranolaImporter {

    static func parseDate(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    static func importDirectory(
        _ directory: URL,
        writer: ObsidianWriter? = nil,
        store: MeetingStore? = nil
    ) throws -> GranolaImportResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GranolaImportError.notADirectory(directory.path)
        }

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let writer = writer ?? ObsidianWriter()
        let store = try store ?? MeetingStore()
        var result = GranolaImportResult()

        for file in files {
            do {
                try importFile(file, writer: writer, store: store, result: &result)
            } catch {
                result.failed.append((file: file.lastPathComponent, error: error.localizedDescription))
            }
        }
        return result
    }

    private static func importFile(
        _ file: URL,
        writer: ObsidianWriter,
        store: MeetingStore,
        result: inout GranolaImportResult
    ) throws {
        let data = try Data(contentsOf: file)
        let record = try JSONDecoder().decode(GranolaExportRecord.self, from: data)
        guard let date = parseDate(record.meeting_at) else {
            throw NSError(domain: "aria.granola", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "meeting_at inválido: \(record.meeting_at)"
            ])
        }

        let externalID = "granola:\(record.id)"
        let existing = try store.existingImportedMeeting(externalID: externalID)

        var body = record.summary_markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { body = "_(sin resumen)_" }
        if let url = record.url, !url.isEmpty {
            body += "\n\n---\n[Ver en Granola](\(url))"
        }

        let note = MeetingNote(
            title: record.title,
            date: date,
            participants: record.participants,
            durationSeconds: 0,
            body: body,
            transcript: record.transcript,
            source: "granola",
            externalID: record.id,
            url: record.url
        )

        let existingPath = existing.map { URL(fileURLWithPath: $0.notePath) }
        let writtenURL = try writer.write(note, overwriting: existingPath)

        var segments: [TranscriptSegment] = []
        if let transcript = record.transcript, !transcript.isEmpty {
            segments = transcript
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { TranscriptSegment(start: 0, end: 0, text: String($0), speaker: "") }
        }
        let quickNotes = record.summary_markdown.isEmpty
            ? []
            : [QuickNote(timestamp: "", text: record.summary_markdown)]

        try store.upsertImportedMeeting(
            externalID: externalID,
            source: "granola",
            date: date,
            title: record.title,
            durationSeconds: 0,
            notePath: writtenURL.path,
            segments: segments,
            quickNotes: quickNotes
        )

        if existing != nil {
            result.updated += 1
        } else {
            result.imported += 1
        }
    }
}
