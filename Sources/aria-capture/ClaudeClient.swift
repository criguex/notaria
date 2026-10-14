import Foundation

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case httpError(status: Int, type: String, message: String)
    case invalidResponse
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return KeychainStore.setupInstructions
        case .httpError(let status, let type, let message):
            return "Claude API HTTP \(status) (\(type)): \(message)"
        case .invalidResponse:
            return "Respuesta inesperada del API de Claude."
        case .refused(let detail):
            return "Claude rechazó la petición: \(detail)"
        }
    }
}

struct ClaudeResult {
    let text: String
    let stopReason: String
    let inputTokens: Int
    let outputTokens: Int
}

final class ClaudeClient {

    static var defaultModel: String { AriaConfig.load().claudeModel }

    private let apiKey: String
    private let model: String
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(model: String = ClaudeClient.defaultModel) throws {
        guard let key = KeychainStore.anthropicAPIKey() else {
            throw ClaudeError.missingAPIKey
        }
        self.apiKey = key
        self.model = model
    }

    func complete(
        system: String,
        userMessage: String,
        maxTokens: Int = 16_000,
        onText: ((String) -> Void)? = nil
    ) async throws -> ClaudeResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 600

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": system,
            "messages": [["role": "user", "content": userMessage]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        guard http.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            let parsed = Self.parseErrorBody(errorBody)
            throw ClaudeError.httpError(status: http.statusCode, type: parsed.type, message: parsed.message)
        }

        var text = ""
        var stopReason = ""
        var inputTokens = 0
        var outputTokens = 0

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = line.dropFirst(6)
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let eventType = event["type"] as? String else { continue }

            switch eventType {
            case "message_start":
                if let message = event["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any] {
                    inputTokens = usage["input_tokens"] as? Int ?? 0
                }
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta",
                   let chunk = delta["text"] as? String {
                    text += chunk
                    onText?(chunk)
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any],
                   let reason = delta["stop_reason"] as? String {
                    stopReason = reason
                }
                if let usage = event["usage"] as? [String: Any],
                   let output = usage["output_tokens"] as? Int {
                    outputTokens = output
                }
            case "error":
                let parsed = Self.parseErrorEvent(event)
                throw ClaudeError.httpError(status: 200, type: parsed.type, message: parsed.message)
            default:
                break
            }
        }

        if stopReason == "refusal" {
            throw ClaudeError.refused("stop_reason=refusal; guarda la nota en modo offline y reintenta.")
        }
        return ClaudeResult(text: text, stopReason: stopReason, inputTokens: inputTokens, outputTokens: outputTokens)
    }

    private static func parseErrorBody(_ body: String) -> (type: String, message: String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("unknown", body.isEmpty ? "sin cuerpo" : String(body.prefix(300)))
        }
        return parseErrorEvent(json)
    }

    private static func parseErrorEvent(_ json: [String: Any]) -> (type: String, message: String) {
        guard let error = json["error"] as? [String: Any] else {
            return ("unknown", "formato de error desconocido")
        }
        return (error["type"] as? String ?? "unknown", error["message"] as? String ?? "sin mensaje")
    }
}
