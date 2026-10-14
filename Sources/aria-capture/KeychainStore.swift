import Foundation
import Security

enum KeychainStore {

    static let anthropicService = "aria-anthropic"
    static let openAICompatibleService = "aria-openai-compatible"
    static let slackService = "aria-slack"

    static func anthropicAPIKey() -> String? {
        guard let key = KeychainCLI.read(service: anthropicService, account: "aria"),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    @discardableResult
    static func saveAnthropicAPIKey(_ key: String) -> Bool {
        KeychainCLI.write(service: anthropicService, account: "aria", secret: key)
    }

    static func openAICompatibleAPIKey() -> String? {
        guard let key = KeychainCLI.read(service: openAICompatibleService, account: "aria"),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    @discardableResult
    static func saveOpenAICompatibleAPIKey(_ key: String) -> Bool {
        KeychainCLI.write(service: openAICompatibleService, account: "aria", secret: key)
    }

    static func slackWebhookURL() -> String? {
        guard let value = KeychainCLI.read(service: slackService, account: "aria"),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    @discardableResult
    static func saveSlackWebhookURL(_ url: String) -> Bool {
        KeychainCLI.write(service: slackService, account: "aria", secret: url)
    }

    static let setupInstructions = """
    Falta la API key de Anthropic en el Keychain. Guárdala con:
      security add-generic-password -s aria-anthropic -a aria -w 'sk-ant-...' -U
    (la key se obtiene en https://console.anthropic.com → API Keys)
    """
}
