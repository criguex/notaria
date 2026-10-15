import Foundation

enum KeychainCLI {

    static var executablePath = "/usr/bin/security"
    static var timeoutSeconds: TimeInterval = 5

    static func read(service: String, account: String) -> String? {
        let output = run(["find-generic-password", "-s", service, "-a", account, "-w"])
        guard let output, !output.isEmpty else { return nil }
        return output
    }

    @discardableResult
    static func write(service: String, account: String, secret: String) -> Bool {
        run(["add-generic-password", "-s", service, "-a", account, "-w", secret, "-U"]) != nil
    }

    /// `security` puede quedarse colgado para siempre (por ejemplo si el keychain está bloqueado
    /// y no hay sesión interactiva para desbloquearlo: la app corre en background/login item sin
    /// terminal). Sin tope de tiempo, `readDataToEndOfFile()` nunca retorna y TODA la app se cuelga
    /// en silencio (cero CPU, sin mensaje) la primera vez que toca Keychain (API keys, cifrado del
    /// historial). Por eso se mata el proceso si no termina en `timeoutSeconds`.
    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        let watchdog = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: watchdog)

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        watchdog.cancel()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
