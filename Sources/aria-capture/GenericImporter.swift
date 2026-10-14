import CryptoKit
import Foundation

enum ImportError: LocalizedError {
    case notFound(String)
    case unsupportedFormat(String)
    case invalidRecord(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "No existe la ruta: \(path)"
        case .unsupportedFormat(let ext):
            return "Formato no soportado: .\(ext)"
        case .invalidRecord(let detail):
            return detail
        }
    }
}

struct ImportResult {
    var imported = 0
    var updated = 0
    var failed: [(file: String, error: String)] = []
}

private struct ImportedItem {
    var title: String
    var date: Date
    var attendees: [String]
    var body: String
    var transcript: String?
    var segments: [TranscriptSegment]
    var source: String
    var rawID: String
    var url: String?
}

private struct Frontmatter {
    var title: String?
    var date: String?
    var attendees: [String]?
    var source: String?
    var id: String?
}

private struct GenericImportJSONRecord: Decodable {
    let source: String?
    let id: String?
    let title: String?
    let date: String?
    let meeting_at: String?
    let attendees: [String]?
    let participants: [String]?
    let body: String?
    let summary_markdown: String?
    let transcript: String?
    let url: String?
}

enum GenericImporter {

    private static let supportedExtensions: Set<String> = ["md", "txt", "vtt", "srt", "json"]

    static func importPath(
        _ path: URL,
        sourceOverride: String?,
        writer: ObsidianWriter? = nil,
        store: MeetingStore? = nil
    ) throws -> ImportResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
            throw ImportError.notFound(path.path)
        }
        let writer = writer ?? ObsidianWriter()
        let store = try store ?? MeetingStore()
        var result = ImportResult()

        let files = isDirectory.boolValue ? collectFiles(in: path) : [path]
        for file in files {
            do {
                let items = try importFile(file, sourceOverride: sourceOverride)
                for item in items {
                    try apply(item, writer: writer, store: store, result: &result)
                }
            } catch {
                result.failed.append((file: file.lastPathComponent, error: error.localizedDescription))
            }
        }
        return result
    }

    private static func collectFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for entry in enumerator {
            guard let url = entry as? URL else { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir, supportedExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func importFile(_ file: URL, sourceOverride: String?) throws -> [ImportedItem] {
        switch file.pathExtension.lowercased() {
        case "md", "txt":
            return try importMarkdown(file, sourceOverride: sourceOverride)
        case "vtt":
            return try importSubtitle(file, sourceOverride: sourceOverride, defaultSource: "vtt")
        case "srt":
            return try importSubtitle(file, sourceOverride: sourceOverride, defaultSource: "srt")
        case "json":
            return try importJSON(file, sourceOverride: sourceOverride)
        default:
            throw ImportError.unsupportedFormat(file.pathExtension)
        }
    }

    private static func apply(
        _ item: ImportedItem,
        writer: ObsidianWriter,
        store: MeetingStore,
        result: inout ImportResult
    ) throws {
        let externalID = "\(item.source):\(item.rawID)"
        let existing = try store.existingImportedMeeting(externalID: externalID)
        let note = MeetingNote(
            title: item.title,
            date: item.date,
            participants: item.attendees,
            durationSeconds: 0,
            body: item.body,
            transcript: item.transcript,
            source: item.source,
            externalID: item.rawID,
            url: item.url
        )
        let existingPath = existing.map { URL(fileURLWithPath: $0.notePath) }
        let writtenURL = try writer.write(note, overwriting: existingPath)
        let quickNotes = item.body.isEmpty ? [] : [QuickNote(timestamp: "", text: item.body)]
        try store.upsertImportedMeeting(
            externalID: externalID,
            source: item.source,
            date: item.date,
            title: item.title,
            durationSeconds: 0,
            notePath: writtenURL.path,
            segments: item.segments,
            quickNotes: quickNotes
        )
        if existing != nil {
            result.updated += 1
        } else {
            result.imported += 1
        }
    }

    // MARK: - Markdown / texto

    private static func importMarkdown(_ file: URL, sourceOverride: String?) throws -> [ImportedItem] {
        let raw = try String(contentsOf: file, encoding: .utf8)
        let (frontmatter, body) = parseFrontmatter(raw)
        let title = nonEmpty(frontmatter?.title) ?? titleFromFilename(file)

        let date: Date
        if let dateString = frontmatter?.date {
            guard let parsed = parseFlexibleDate(dateString) else {
                throw ImportError.invalidRecord("fecha inválida: \(dateString)")
            }
            date = parsed
        } else {
            date = modificationDate(file)
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalBody = trimmedBody.isEmpty ? "_(sin contenido)_" : trimmedBody
        let source = sourceOverride ?? frontmatter?.source ?? "notes"
        let rawID = frontmatter?.id ?? contentHash(Data(raw.utf8))

        return [ImportedItem(
            title: title,
            date: date,
            attendees: frontmatter?.attendees ?? [],
            body: finalBody,
            transcript: nil,
            segments: [],
            source: source,
            rawID: rawID,
            url: nil
        )]
    }

    private static func parseFrontmatter(_ content: String) -> (Frontmatter?, String) {
        guard content.hasPrefix("---") else { return (nil, content) }
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, content) }
        guard let closing = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return (nil, content)
        }
        let yaml = lines[1..<closing]
        let body = lines[(closing + 1)...].joined(separator: "\n")

        var fm = Frontmatter()
        for line in yaml {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let rawValue = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "title": fm.title = stripQuotes(rawValue)
            case "date": fm.date = stripQuotes(rawValue)
            case "source": fm.source = stripQuotes(rawValue)
            case "id": fm.id = stripQuotes(rawValue)
            case "attendees": fm.attendees = parseListValue(rawValue)
            default: break
            }
        }
        return (fm, body)
    }

    private static func parseListValue(_ raw: String) -> [String] {
        var value = raw
        if value.hasPrefix("[") && value.hasSuffix("]") {
            value = String(value.dropFirst().dropLast())
        }
        return value.split(separator: ",")
            .map { stripQuotes($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func stripQuotes(_ value: String) -> String {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard v.count >= 2 else { return v }
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            return String(v.dropFirst().dropLast())
        }
        return v
    }

    // MARK: - VTT / SRT

    private static func importSubtitle(_ file: URL, sourceOverride: String?, defaultSource: String) throws -> [ImportedItem] {
        let data = try Data(contentsOf: file)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidRecord("no se pudo leer \(file.lastPathComponent) como texto UTF-8")
        }
        let segments = SubtitleParser.parse(raw)
        let transcript = TranscriptFormatter.render(segments)
        let source = sourceOverride ?? defaultSource

        return [ImportedItem(
            title: titleFromFilename(file),
            date: modificationDate(file),
            attendees: orderedUniqueSpeakers(segments),
            body: "_(sin resumen — transcript importado)_",
            transcript: transcript.isEmpty ? nil : transcript,
            segments: segments,
            source: source,
            rawID: contentHash(data),
            url: nil
        )]
    }

    private static func orderedUniqueSpeakers(_ segments: [TranscriptSegment]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for segment in segments where !segment.speaker.isEmpty {
            if seen.insert(segment.speaker).inserted {
                result.append(segment.speaker)
            }
        }
        return result
    }

    // MARK: - JSON

    private static func importJSON(_ file: URL, sourceOverride: String?) throws -> [ImportedItem] {
        let data = try Data(contentsOf: file)
        let baseTitle = titleFromFilename(file)
        let mtime = modificationDate(file)

        if let array = try? JSONDecoder().decode([GenericImportJSONRecord].self, from: data) {
            guard !array.isEmpty else {
                throw ImportError.invalidRecord("JSON vacío: \(file.lastPathComponent)")
            }
            return try array.enumerated().map { index, record in
                try makeItem(
                    record,
                    sourceOverride: sourceOverride,
                    fallbackTitle: array.count == 1 ? baseTitle : "\(baseTitle) \(index + 1)",
                    fallbackDate: mtime
                )
            }
        }
        let record = try JSONDecoder().decode(GenericImportJSONRecord.self, from: data)
        return [try makeItem(record, sourceOverride: sourceOverride, fallbackTitle: baseTitle, fallbackDate: mtime)]
    }

    private static func makeItem(
        _ record: GenericImportJSONRecord,
        sourceOverride: String?,
        fallbackTitle: String,
        fallbackDate: Date
    ) throws -> ImportedItem {
        let title = nonEmpty(record.title) ?? fallbackTitle
        let dateString = record.date ?? record.meeting_at
        let date: Date
        if let dateString, !dateString.isEmpty {
            guard let parsed = parseFlexibleDate(dateString) else {
                throw ImportError.invalidRecord("fecha inválida: \(dateString)")
            }
            date = parsed
        } else {
            date = fallbackDate
        }

        var body = (record.body ?? record.summary_markdown ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { body = "_(sin resumen)_" }
        if let url = record.url, !url.isEmpty {
            body += "\n\n---\n[Ver original](\(url))"
        }

        var segments: [TranscriptSegment] = []
        if let transcript = record.transcript, !transcript.isEmpty {
            segments = transcript
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { TranscriptSegment(start: 0, end: 0, text: String($0), speaker: "") }
        }

        let source = sourceOverride ?? record.source ?? "json"
        let rawID = record.id ?? contentHash("\(title)|\(dateString ?? "")|\(body)|\(record.transcript ?? "")")

        return ImportedItem(
            title: title,
            date: date,
            attendees: record.attendees ?? record.participants ?? [],
            body: body,
            transcript: record.transcript,
            segments: segments,
            source: source,
            rawID: rawID,
            url: record.url
        )
    }

    // MARK: - Utilidades compartidas

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    private static func titleFromFilename(_ url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let spaced = base.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        let collapsed = spaced.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return collapsed.isEmpty ? "Nota importada" : collapsed
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
    }

    private static func parseFlexibleDate(_ value: String) -> Date? {
        if let date = GranolaImporter.parseDate(value) { return date }
        let dayTime = DateFormatter()
        dayTime.dateFormat = "yyyy-MM-dd HH:mm"
        dayTime.timeZone = .current
        if let date = dayTime.date(from: value) { return date }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = .current
        return day.date(from: value)
    }

    private static func contentHash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256-" + String(hex.prefix(16))
    }

    private static func contentHash(_ string: String) -> String {
        contentHash(Data(string.utf8))
    }
}
