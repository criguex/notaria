import Foundation

final class MCPServer {

    private let store: MeetingStore

    init(store: MeetingStore? = nil) throws {
        self.store = try store ?? MeetingStore()
    }

    static let tools: [[String: Any]] = [
        [
            "name": "search_meetings",
            "description": "Búsqueda full-text (FTS5, insensible a tildes) sobre transcripts, notas y títulos de las reuniones grabadas con Aria.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Palabras a buscar"],
                    "limit": ["type": "integer", "description": "Máximo de resultados (default 10)"]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "list_meetings",
            "description": "Lista las reuniones más recientes del historial de Aria (id, fecha, duración, título).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Máximo de reuniones (default 15)"]
                ]
            ]
        ],
        [
            "name": "get_meeting",
            "description": "Devuelve una reunión completa por id: título, fecha, transcript diarizado y notas rápidas.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": ["type": "integer", "description": "Id de la reunión (ver list_meetings)"]
                ],
                "required": ["id"]
            ]
        ]
    ]

    func run() {
        FileHandle.standardError.write(Data("[mcp] Aria MCP server listo (stdio, solo lectura). Ctrl+C para salir.\n".utf8))
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let response = handle(line) {
                print(response)
                fflush(stdout)
            }
        }
    }

    func handle(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        guard let id = request["id"] else { return nil }
        let method = request["method"] as? String ?? ""
        switch method {
        case "initialize":
            return encode(id: id, result: [
                "protocolVersion": (request["params"] as? [String: Any])?["protocolVersion"] as? String ?? "2024-11-05",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "aria", "version": "1.0.0"]
            ])
        case "ping":
            return encode(id: id, result: [:])
        case "tools/list":
            return encode(id: id, result: ["tools": Self.tools])
        case "tools/call":
            return toolCall(id: id, params: request["params"] as? [String: Any] ?? [:])
        default:
            return encodeError(id: id, code: -32601, message: "Método no soportado: \(method)")
        }
    }

    private func toolCall(id: Any, params: [String: Any]) -> String {
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        do {
            let text: String
            switch params["name"] as? String ?? "" {
            case "search_meetings":
                guard let query = arguments["query"] as? String else {
                    return toolText(id: id, "Falta el argumento 'query'.", isError: true)
                }
                let hits = try MeetingSearch.search(query, store: store, limit: Self.intValue(arguments["limit"]) ?? 10)
                text = hits.isEmpty
                    ? "Sin resultados para \"\(query)\"."
                    : hits.map(MeetingSearch.line(for:)).joined(separator: "\n")
            case "list_meetings":
                let records = try store.recentMeetings(limit: Self.intValue(arguments["limit"]) ?? 15)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                text = records.isEmpty
                    ? "Sin reuniones en el historial todavía."
                    : records.map { record in
                        let minutes = Int(record.durationSeconds) / 60
                        return "[\(record.id)] \(formatter.string(from: record.date)) · \(minutes) min · \(record.title)"
                    }.joined(separator: "\n")
            case "get_meeting":
                guard let meetingID = Self.intValue(arguments["id"]) else {
                    return toolText(id: id, "Falta el argumento 'id' (entero).", isError: true)
                }
                guard let record = try store.recentMeetings(limit: 10_000).first(where: { $0.id == Int64(meetingID) }) else {
                    return toolText(id: id, "No existe la reunión [\(meetingID)].", isError: true)
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                let transcript = TranscriptFormatter.render(try store.segments(meetingID: record.id))
                let notes = try store.quickNotes(meetingID: record.id)
                var output = "# \(record.title)\nFecha: \(formatter.string(from: record.date)) · Duración: \(Int(record.durationSeconds) / 60) min\n"
                if !notes.isEmpty {
                    output += "\n## Notas del usuario\n" + notes.map { $0.timestamp.isEmpty ? "- \($0.text)" : "- [\($0.timestamp)] \($0.text)" }.joined(separator: "\n") + "\n"
                }
                output += "\n## Transcript\n" + (transcript.isEmpty ? "(sin voz detectada)" : transcript)
                text = output
            default:
                return toolText(id: id, "Tool desconocida: \(params["name"] as? String ?? "?")", isError: true)
            }
            return toolText(id: id, text)
        } catch {
            return toolText(id: id, error.localizedDescription, isError: true)
        }
    }

    static func intValue(_ raw: Any?) -> Int? {
        (raw as? Int) ?? (raw as? String).flatMap(Int.init)
    }

    private func toolText(id: Any, _ text: String, isError: Bool = false) -> String {
        var result: [String: Any] = ["content": [["type": "text", "text": text]]]
        if isError { result["isError"] = true }
        return encode(id: id, result: result)
    }

    private func encode(id: Any, result: [String: Any]) -> String {
        serialize(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func encodeError(id: Any, code: Int, message: String) -> String {
        serialize(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private func serialize(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Error interno serializando"}}"#
        }
        return json
    }
}
