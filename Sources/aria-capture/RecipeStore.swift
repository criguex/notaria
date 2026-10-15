import Foundation

struct Recipe: Equatable {
    let name: String
    let prompt: String
}

final class RecipeStore {

    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? AriaHome.directory
            .appendingPathComponent("Documents/Aria/Recipes")
    }

    static let defaults: [String: String] = [
        "follow-up-email": """
        Redacta el correo de follow-up de esta reunión, listo para enviar.
        - Asunto claro que resuma la reunión.
        - Saludo breve y agradecimiento por el tiempo.
        - Resumen de lo conversado en 2-3 líneas.
        - Acuerdos y decisiones en viñetas.
        - Action items con responsable y fecha (los del usuario en primera persona).
        - Cierre cordial invitando a corregir si algo quedó mal recogido.
        Escríbelo en el idioma de la reunión. Responde SOLO con el correo (Asunto + cuerpo).
        """,
        "action-items": """
        Extrae TODOS los action items de la(s) reunión(es) del contexto como checklist Markdown:
        - [ ] <acción concreta> — responsable — fecha si se dijo
        Incluye solo compromisos reales, no ideas sueltas. Si el responsable no está claro,
        márcalo como "(por confirmar)". Responde SOLO con la checklist.
        """,
        "resumen-ejecutivo": """
        Escribe un resumen ejecutivo de máximo 5 viñetas de la(s) reunión(es): qué se decidió,
        qué sigue, y riesgos si los hay. Directo y sin relleno. Responde SOLO con las viñetas.
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

    func recipe(named name: String) -> Recipe? {
        list().first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }
}
