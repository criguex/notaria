import Foundation

enum AIProviderKind: String, Codable, CaseIterable {
    case auto
    case claudeCLI
    case anthropicAPI
    case openAICompatible
    case ollama

    var label: String {
        switch self {
        case .auto: return "Automático (API con key si hay, si no Claude CLI)"
        case .claudeCLI: return "Claude Code CLI"
        case .anthropicAPI: return "Anthropic API (key propia)"
        case .openAICompatible: return "OpenAI-compatible (OpenAI, OpenRouter, Groq, LM Studio)"
        case .ollama: return "Ollama (local)"
        }
    }

    var isLocal: Bool { self == .ollama }

    var needsModelField: Bool { self == .openAICompatible || self == .ollama }

    var needsBaseURLField: Bool { self == .openAICompatible || self == .ollama }

    var needsAPIKeyField: Bool { self == .anthropicAPI || self == .openAICompatible }

    var privacyNote: String {
        switch self {
        case .ollama:
            return "Local: el transcript y tus notas se quedan en tu Mac, nada sale a internet."
        case .claudeCLI:
            return "Usa tu sesión de Claude Code: el transcript y tus notas salen hacia Anthropic."
        case .anthropicAPI:
            return "El transcript y tus notas salen hacia la API de Anthropic con tu API key."
        case .openAICompatible:
            return "El transcript y tus notas salen hacia el servidor que configures (OpenAI, OpenRouter, Groq u otro)."
        case .auto:
            return "Usa Anthropic (API si hay key, si no CLI): el transcript y tus notas salen hacia Anthropic."
        }
    }
}

enum AIProviderFactory {

    static func makeBackend(config: AriaConfig = AriaConfig.load()) -> EnhanceBackend? {
        switch config.aiProvider {
        case .auto:
            if let api = try? ClaudeClient() {
                return api
            }
            return try? ClaudeCLIClient()
        case .claudeCLI:
            return try? ClaudeCLIClient()
        case .anthropicAPI:
            return try? ClaudeClient(model: config.claudeModel)
        case .openAICompatible:
            return try? OpenAICompatibleClient(
                baseURL: config.aiBaseURL,
                model: config.aiModel,
                apiKey: KeychainStore.openAICompatibleAPIKey()
            )
        case .ollama:
            return try? OllamaClient(
                baseURL: config.aiBaseURL,
                model: config.aiModel
            )
        }
    }
}
