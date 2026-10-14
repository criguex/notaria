import Foundation

enum OpenAICompatibleError: LocalizedError {
    case missingConfig
    case invalidResponse
    case httpError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "Falta la URL base o el modelo del proveedor OpenAI-compatible (ver Ajustes › Modelo de IA)."
        case .invalidResponse:
            return "Respuesta inesperada del proveedor OpenAI-compatible."
        case .httpError(let status, let message):
            return "OpenAI-compatible HTTP \(status): \(message)"
        }
    }
}

final class OpenAICompatibleClient: EnhanceBackend {

    let baseURL: String
    let model: String
    private let apiKey: String?
    private let session: URLSession

    var backendName: String { "OpenAI-compatible (\(model) · \(baseURL))" }

    init(baseURL: String, model: String, apiKey: String?, session: URLSession = .shared) throws {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty, !trimmedModel.isEmpty else {
            throw OpenAICompatibleError.missingConfig
        }
        self.baseURL = trimmedBase
        self.model = trimmedModel
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = (trimmedKey?.isEmpty ?? true) ? nil : trimmedKey
        self.session = session
    }

    static func stripTrailingSlashes(_ value: String) -> String {
        var result = value
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    static func endpoint(baseURL: String) -> URL? {
        let trimmed = stripTrailingSlashes(baseURL)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        return URL(string: trimmed + "/chat/completions")
    }

    static func modelsEndpoint(baseURL: String) -> URL? {
        let trimmed = stripTrailingSlashes(baseURL)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("/models") {
            return URL(string: trimmed)
        }
        return URL(string: trimmed + "/models")
    }

    static func requestBody(system: String, userMessage: String, model: String, maxTokens: Int) -> [String: Any] {
        [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userMessage]
            ]
        ]
    }

    func complete(
        system: String,
        userMessage: String,
        maxTokens: Int = 16_000,
        onText: ((String) -> Void)? = nil
    ) async throws -> ClaudeResult {
        guard let url = Self.endpoint(baseURL: baseURL) else {
            throw OpenAICompatibleError.missingConfig
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 600
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.requestBody(system: system, userMessage: userMessage, model: model, maxTokens: maxTokens)
        )

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAICompatibleError.invalidResponse
        }
        guard http.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw OpenAICompatibleError.httpError(status: http.statusCode, message: Self.parseErrorMessage(errorBody))
        }

        var text = ""
        var inputTokens = 0
        var outputTokens = 0
        var finishReason = "end_turn"

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let usage = event["usage"] as? [String: Any] {
                inputTokens = usage["prompt_tokens"] as? Int ?? inputTokens
                outputTokens = usage["completion_tokens"] as? Int ?? outputTokens
            }
            guard let choices = event["choices"] as? [[String: Any]], let choice = choices.first else { continue }
            if let delta = choice["delta"] as? [String: Any], let chunk = delta["content"] as? String, !chunk.isEmpty {
                text += chunk
                onText?(chunk)
            }
            if let reason = choice["finish_reason"] as? String {
                finishReason = reason
            }
        }
        return ClaudeResult(text: text, stopReason: finishReason, inputTokens: inputTokens, outputTokens: outputTokens)
    }

    static func parseErrorMessage(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return body.isEmpty ? "sin detalle" : String(body.prefix(300))
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let error = json["error"] as? String {
            return error
        }
        return body.isEmpty ? "sin detalle" : String(body.prefix(300))
    }
}
