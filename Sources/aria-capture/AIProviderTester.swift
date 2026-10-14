import Foundation

struct AIProviderTestResult {
    let ok: Bool
    let message: String
}

enum AIProviderTester {

    static func test(
        config: AriaConfig,
        session: URLSession = .shared,
        anthropicKeyProvider: () -> String? = KeychainStore.anthropicAPIKey,
        openAIKeyProvider: () -> String? = KeychainStore.openAICompatibleAPIKey
    ) async -> AIProviderTestResult {
        switch config.aiProvider {
        case .auto:
            return await testAuto(session: session, anthropicKeyProvider: anthropicKeyProvider)
        case .claudeCLI:
            return testClaudeCLI()
        case .anthropicAPI:
            return await testAnthropicAPI(session: session, keyProvider: anthropicKeyProvider)
        case .openAICompatible:
            return await testOpenAICompatible(config: config, session: session, keyProvider: openAIKeyProvider)
        case .ollama:
            return await testOllama(config: config, session: session)
        }
    }

    private static func testAuto(
        session: URLSession,
        anthropicKeyProvider: () -> String?
    ) async -> AIProviderTestResult {
        guard anthropicKeyProvider() != nil else {
            return testClaudeCLI()
        }
        let result = await testAnthropicAPI(session: session, keyProvider: anthropicKeyProvider)
        return AIProviderTestResult(ok: result.ok, message: "Automático → Anthropic API. " + result.message)
    }

    private static func testClaudeCLI() -> AIProviderTestResult {
        guard let client = try? ClaudeCLIClient() else {
            return AIProviderTestResult(ok: false, message: ClaudeCLIError.notInstalled.localizedDescription)
        }
        return AIProviderTestResult(ok: true, message: "\(client.backendName) encontrado.")
    }

    private static func testAnthropicAPI(
        session: URLSession,
        keyProvider: () -> String?
    ) async -> AIProviderTestResult {
        guard let key = keyProvider() else {
            return AIProviderTestResult(ok: false, message: KeychainStore.setupInstructions)
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return await probeEndpoint(request: request, session: session, okMessage: "Anthropic API: conexión y key verificadas.")
    }

    private static func testOpenAICompatible(
        config: AriaConfig,
        session: URLSession,
        keyProvider: () -> String?
    ) async -> AIProviderTestResult {
        let trimmedBase = config.aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty, let url = OpenAICompatibleClient.modelsEndpoint(baseURL: trimmedBase) else {
            return AIProviderTestResult(ok: false, message: "Falta la URL base (ej. https://api.openai.com/v1).")
        }
        var request = URLRequest(url: url)
        if let key = keyProvider(), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return await probeEndpoint(
            request: request,
            session: session,
            okMessage: "OpenAI-compatible: conexión verificada en \(trimmedBase)."
        )
    }

    private static func testOllama(config: AriaConfig, session: URLSession) async -> AIProviderTestResult {
        let trimmedBase = config.aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedBase.isEmpty ? OllamaClient.defaultBaseURL : trimmedBase
        guard let url = OllamaClient.tagsEndpoint(baseURL: base) else {
            return AIProviderTestResult(ok: false, message: "URL de Ollama inválida: \(base)")
        }
        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return AIProviderTestResult(
                    ok: false,
                    message: "Ollama no respondió en \(base) (¿está corriendo 'ollama serve'?)."
                )
            }
            let models = OllamaClient.parseModelNames(data)
            let detail = models.isEmpty ? "sin modelos descargados todavía" : "modelos: \(models.joined(separator: ", "))"
            return AIProviderTestResult(ok: true, message: "Ollama responde en \(base) (\(detail)).")
        } catch {
            return AIProviderTestResult(ok: false, message: "No se pudo conectar a Ollama en \(base): \(error.localizedDescription)")
        }
    }

    private static func probeEndpoint(
        request: URLRequest,
        session: URLSession,
        okMessage: String
    ) async -> AIProviderTestResult {
        var request = request
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return AIProviderTestResult(ok: false, message: "Respuesta inesperada.")
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return AIProviderTestResult(
                    ok: false,
                    message: "HTTP \(http.statusCode): \(body.isEmpty ? "sin detalle" : String(body.prefix(200)))"
                )
            }
            return AIProviderTestResult(ok: true, message: okMessage)
        } catch {
            return AIProviderTestResult(ok: false, message: error.localizedDescription)
        }
    }
}
