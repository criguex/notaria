import Foundation

struct QuickNote {
    let timestamp: String
    let text: String
}

final class NotesStore {

    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents/Aria", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("notes.md")
        }
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    func append(_ text: String, date: Date = Date()) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let flattened = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let line = "- [\(formatter.string(from: date))] \(flattened)\n"

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            try line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    func all() -> [QuickNote] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ["),
                  let close = trimmed.firstIndex(of: "]") else {
                guard !trimmed.isEmpty else { return nil }
                return QuickNote(timestamp: "", text: trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed)
            }
            let timestamp = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)..<close])
            let text = String(trimmed[trimmed.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            return QuickNote(timestamp: timestamp, text: text)
        }
    }

    var rawMarkdown: String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }
}
