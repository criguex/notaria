import Foundation

final class TemplateStore {

    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Aria/Plantillas")
    }

    static let defaults: [String: String] = [
        "1-1": """
        Es una reunión 1:1. Prioriza: cómo está la persona, temas de carrera/feedback en ambas
        direcciones, acuerdos personales y seguimiento de los del 1:1 anterior si se mencionan.
        Las secciones de Decisiones y Action items deben dejar claro quién de los dos se lleva cada cosa.
        """,
        "ventas": """
        Es una reunión comercial. Prioriza: quién es el cliente y su contexto, necesidades y dolores
        expresados, objeciones y cómo se respondieron, señales de compra, y próximos pasos comerciales
        con responsable y fecha. Cierra el resumen con el estado de la oportunidad en una línea.
        """,
        "standup": """
        Es un standup/daily. Estructura el resumen por persona: qué hizo, qué hará y bloqueos.
        Los action items son SOLO los bloqueos y quién los destraba. Sé especialmente breve.
        """
    ]

    @discardableResult
    func ensureDefaults() throws -> [String] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var created: [String] = []
        for (name, prompt) in Self.defaults.sorted(by: { $0.key < $1.key }) {
            let url = directory.appendingPathComponent("\(name).md")
            if !FileManager.default.fileExists(atPath: url.path) {
                try (prompt + "\n").write(to: url, atomically: true, encoding: .utf8)
                created.append(name)
            }
        }
        return created
    }

    func list() -> [Recipe] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return contents
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let prompt = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !prompt.isEmpty else { return nil }
                return Recipe(name: url.deletingPathExtension().lastPathComponent, prompt: prompt)
            }
    }

    func template(named name: String) -> Recipe? {
        list().first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }
}
