import Foundation

enum OllamaError: LocalizedError {
    case missingModel
    case invalidBaseURL
    case invalidResponse
    case httpError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return "Falta elegir el modelo de Ollama (ver Ajustes › Modelo de IA o 'aria-capture ai test')."
        case .invalidBaseURL:
            return "URL de Ollama inválida."
        case .invalidResponse:
            return "Respuesta inesperada de Ollama."
        case .httpError(let status, let message):
            return "Ollama HTTP \(status): \(message)"
        }
    }
}

final class OllamaClient: EnhanceBackend {

    static let defaultBaseURL = "http://localhost:11434"

    let baseURL: String
    let model: String
    private let session: URLSession

    var backendName: String { "Ollama local (\(model))" }

    init(baseURL: String, model: String, session: URLSession = .shared) throws {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw OllamaError.missingModel
        }
        self.baseURL = trimmedBase.isEmpty ? Self.defaultBaseURL : trimmedBase
        self.model = trimmedModel
        self.session = session
    }

    private static func stripTrailingSlashes(_ value: String) -> String {
        var result = value
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    static func chatEndpoint(baseURL: String) -> URL? {
        let trimmed = stripTrailingSlashes(baseURL)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed + "/api/chat")
    }

    static func tagsEndpoint(baseURL: String) -> URL? {
        let trimmed = stripTrailingSlashes(baseURL)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed + "/api/tags")
    }

    static func requestBody(system: String, userMessage: String, model: String, maxTokens: Int) -> [String: Any] {
        [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userMessage]
            ],
            "options": ["num_predict": maxTokens]
        ]
    }

    func complete(
        system: String,
        userMessage: String,
        maxTokens: Int = 16_000,
        onText: ((String) -> Void)? = nil
    ) async throws -> ClaudeResult {
        guard let url = Self.chatEndpoint(baseURL: baseURL) else {
            throw OllamaError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 600
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.requestBody(system: system, userMessage: userMessage, model: model, maxTokens: maxTokens)
        )

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard http.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw OllamaError.httpError(status: http.statusCode, message: Self.parseErrorMessage(errorBody))
        }

        var text = ""
        var inputTokens = 0
        var outputTokens = 0

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let errorMessage = event["error"] as? String {
                throw OllamaError.httpError(status: 200, message: errorMessage)
            }
            if let message = event["message"] as? [String: Any], let chunk = message["content"] as? String, !chunk.isEmpty {
                text += chunk
                onText?(chunk)
            }
            if event["done"] as? Bool == true {
                inputTokens = event["prompt_eval_count"] as? Int ?? inputTokens
                outputTokens = event["eval_count"] as? Int ?? outputTokens
            }
        }
        return ClaudeResult(text: text, stopReason: "end_turn", inputTokens: inputTokens, outputTokens: outputTokens)
    }

    static func parseModelNames(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    static func listModels(baseURL: String, session: URLSession = .shared) async throws -> [String] {
        guard let url = tagsEndpoint(baseURL: baseURL) else {
            throw OllamaError.invalidBaseURL
        }
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError.invalidResponse
        }
        return parseModelNames(data)
    }

    private static func parseErrorMessage(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return body.isEmpty ? "sin detalle" : String(body.prefix(300))
        }
        if let error = json["error"] as? String {
            return error
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return body.isEmpty ? "sin detalle" : String(body.prefix(300))
    }
}
