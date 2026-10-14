import SwiftUI

@MainActor
final class AIProviderSettingsModel: ObservableObject {
    @Published var provider: AIProviderKind
    @Published var model: String
    @Published var baseURL: String
    @Published var apiKeyInput = ""
    @Published var testing = false
    @Published var testOK = false
    @Published var testResult: String?
    @Published var ollamaModels: [String] = []
    @Published var savedMessage: String?

    init() {
        let config = AriaConfig.load()
        provider = config.aiProvider
        model = config.aiModel
        baseURL = config.aiBaseURL
    }

    func save() {
        var config = AriaConfig.load()
        config.aiProvider = provider
        config.aiModel = model
        config.aiBaseURL = baseURL
        do {
            try config.save()
            savedMessage = "Guardado."
        } catch {
            savedMessage = "Error: \(error.localizedDescription)"
        }
    }

    func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ok: Bool
        switch provider {
        case .anthropicAPI, .auto:
            ok = KeychainStore.saveAnthropicAPIKey(trimmed)
        case .openAICompatible:
            ok = KeychainStore.saveOpenAICompatibleAPIKey(trimmed)
        case .claudeCLI, .ollama:
            ok = false
        }
        apiKeyInput = ""
        savedMessage = ok ? "Key guardada en Keychain." : "Este proveedor no usa key."
    }

    func test() {
        testing = true
        testResult = nil
        var config = AriaConfig.load()
        config.aiProvider = provider
        config.aiModel = model
        config.aiBaseURL = baseURL
        Task {
            let result = await AIProviderTester.test(config: config)
            testOK = result.ok
            testResult = result.message
            testing = false
        }
    }

    func loadOllamaModels() {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? OllamaClient.defaultBaseURL : baseURL
        Task {
            ollamaModels = (try? await OllamaClient.listModels(baseURL: base)) ?? []
        }
    }
}

struct AIProviderSettingsSection: View {
    @StateObject private var model = AIProviderSettingsModel()

    var body: some View {
        Section("Modelo de IA") {
            Picker("Proveedor", selection: $model.provider) {
                ForEach(AIProviderKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }

            if model.provider.needsBaseURLField {
                TextField(
                    model.provider == .ollama ? "URL (vacío = \(OllamaClient.defaultBaseURL))" : "URL base (ej. https://api.openai.com/v1)",
                    text: $model.baseURL
                )
            }

            if model.provider.needsModelField {
                if model.provider == .ollama {
                    HStack {
                        TextField("Modelo", text: $model.model)
                        Button("Cargar modelos") { model.loadOllamaModels() }
                    }
                    if !model.ollamaModels.isEmpty {
                        Picker("Modelos detectados", selection: $model.model) {
                            ForEach(model.ollamaModels, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                } else {
                    TextField("Modelo (ej. gpt-4o-mini)", text: $model.model)
                }
            }

            if model.provider.needsAPIKeyField {
                HStack {
                    SecureField("API key (se guarda en Keychain)", text: $model.apiKeyInput)
                    Button("Guardar key") { model.saveKey() }
                        .disabled(model.apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Text(model.provider.privacyNote)
                .font(.caption)
                .foregroundStyle(model.provider.isLocal ? .green : .secondary)

            HStack {
                Button("Probar conexión") { model.test() }
                    .disabled(model.testing)
                if model.testing {
                    ProgressView().controlSize(.small)
                }
            }
            if let testResult = model.testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(model.testOK ? .green : .red)
            }

            Button("Guardar proveedor") { model.save() }
            if let savedMessage = model.savedMessage {
                Text(savedMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
