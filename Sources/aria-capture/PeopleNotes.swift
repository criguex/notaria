import Foundation

enum PeopleNotes {

    static let publicMailProviders: Set<String> = [
        "gmail", "googlemail", "outlook", "hotmail", "live", "msn", "yahoo",
        "icloud", "me", "mac", "proton", "protonmail", "aol", "gmx", "mail"
    ]

    static func personName(fromWikilink value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[["), trimmed.hasSuffix("]]") else { return nil }
        let name = trimmed.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    static func company(fromAddress address: String) -> String? {
        let raw = address.hasPrefix("mailto:") ? String(address.dropFirst("mailto:".count)) : address
        guard let atIndex = raw.firstIndex(of: "@") else { return nil }
        let domain = raw[raw.index(after: atIndex)...].lowercased()
        guard let firstLabel = domain.split(separator: ".").first.map(String.init), !firstLabel.isEmpty else {
            return nil
        }
        guard !publicMailProviders.contains(firstLabel) else { return nil }
        return firstLabel.prefix(1).uppercased() + firstLabel.dropFirst()
    }

    @discardableResult
    static func ensureStubs(people: [String], companies: [String], notesDirectory: URL, date: Date = Date()) throws -> [URL] {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let day = dayFormatter.string(from: date)
        let root = notesDirectory.deletingLastPathComponent()

        var created: [URL] = []
        for (folder, names, tipo) in [("Personas", people, "persona"), ("Empresas", companies, "empresa")] {
            guard !names.isEmpty else { continue }
            let dir = root.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in CalendarMeeting.uniqueAttendees(names) {
                let file = dir.appendingPathComponent("\(ObsidianWriter.sanitized(name)).md")
                guard !FileManager.default.fileExists(atPath: file.path) else { continue }
                let content = """
                ---
                titulo: \(ObsidianWriter.yamlQuoted(name))
                tipo: \(tipo)
                creado: \(day)
                fuente: aria
                tags: [\(tipo), aria]
                ---

                # \(name)

                _Nota creada por Aria. Los backlinks de Obsidian muestran todas las reuniones donde aparece._

                """
                try content.write(to: file, atomically: true, encoding: .utf8)
                created.append(file)
            }
        }
        return created
    }
}
