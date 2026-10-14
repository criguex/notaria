import Foundation

protocol EnhanceBackend {
    var backendName: String { get }
    func complete(
        system: String,
        userMessage: String,
        maxTokens: Int,
        onText: ((String) -> Void)?
    ) async throws -> ClaudeResult
}

extension ClaudeClient: EnhanceBackend {
    var backendName: String { "API (\(ClaudeClient.defaultModel))" }
}

enum ClaudeCLIError: LocalizedError {
    case notInstalled
    case failed(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "No se encontró el CLI de Claude Code (busqué claude en /opt/homebrew/bin y /usr/local/bin)."
        case .failed(let status, let stderr):
            return "El CLI de Claude falló (exit \(status)): \(stderr.isEmpty ? "sin detalle" : String(stderr.prefix(300)))"
        }
    }
}

final class ClaudeCLIClient: EnhanceBackend {

    private let executable: URL
    private let model: String

    var backendName: String { "Claude Code CLI (suscripción, \(model))" }

    init() throws {
        let candidates = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ClaudeCLIError.notInstalled
        }
        executable = URL(fileURLWithPath: path)
        model = AriaConfig.load().claudeModel
    }

    func complete(
        system: String,
        userMessage: String,
        maxTokens: Int = 16_000,
        onText: ((String) -> Void)? = nil
    ) async throws -> ClaudeResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "-p", userMessage,
            "--append-system-prompt", system,
            "--model", model,
            "--output-format", "text"
        ]
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CLAUDECODE")
        environment.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardInput = FileHandle.nullDevice
        process.standardError = stderr

        try process.run()
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0, !text.isEmpty else {
            throw ClaudeCLIError.failed(
                status: process.terminationStatus,
                stderr: String(data: errorData, encoding: .utf8) ?? ""
            )
        }
        onText?(text)
        return ClaudeResult(text: text, stopReason: "end_turn", inputTokens: 0, outputTokens: 0)
    }

    static func preferredBackend() -> EnhanceBackend? {
        AIProviderFactory.makeBackend()
    }
}
