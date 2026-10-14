import Foundation

enum KeychainCLI {

    static func read(service: String, account: String) -> String? {
        let output = run(["find-generic-password", "-s", service, "-a", account, "-w"])
        guard let output, !output.isEmpty else { return nil }
        return output
    }

    @discardableResult
    static func write(service: String, account: String, secret: String) -> Bool {
        run(["add-generic-password", "-s", service, "-a", account, "-w", secret, "-U"]) != nil
    }

    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
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
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
