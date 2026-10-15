import XCTest
@testable import aria_capture

final class KeychainCLITests: XCTestCase {

    private var originalExecutablePath: String!
    private var originalTimeout: TimeInterval!
    private var scriptDir: URL!

    override func setUpWithError() throws {
        originalExecutablePath = KeychainCLI.executablePath
        originalTimeout = KeychainCLI.timeoutSeconds
        scriptDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-keychain-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        KeychainCLI.executablePath = originalExecutablePath
        KeychainCLI.timeoutSeconds = originalTimeout
        try? FileManager.default.removeItem(at: scriptDir)
    }

    private func writeScript(named name: String, body: String) throws -> String {
        let url = scriptDir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    func testRunDoesNotHangForeverWhenUnderlyingProcessBlocks() throws {
        KeychainCLI.executablePath = try writeScript(named: "hung-security.sh", body: "#!/bin/sh\nsleep 30\n")
        KeychainCLI.timeoutSeconds = 0.3

        let start = Date()
        let result = KeychainCLI.read(service: "whatever", account: "aria")
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNil(result)
        XCTAssertLessThan(elapsed, 5, "KeychainCLI.run debe matar el proceso colgado en vez de esperarlo para siempre")
    }

    func testWriteReturnsFalseWithoutHangingWhenUnderlyingProcessBlocks() throws {
        KeychainCLI.executablePath = try writeScript(named: "hung-security.sh", body: "#!/bin/sh\nsleep 30\n")
        KeychainCLI.timeoutSeconds = 0.3

        let start = Date()
        let ok = KeychainCLI.write(service: "whatever", account: "aria", secret: "s3cret")
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(ok)
        XCTAssertLessThan(elapsed, 5)
    }

    func testRunReturnsOutputWhenProcessExitsPromptly() throws {
        KeychainCLI.executablePath = try writeScript(named: "fast-security.sh", body: "#!/bin/sh\necho hello-world\n")
        KeychainCLI.timeoutSeconds = 5

        let result = KeychainCLI.read(service: "whatever", account: "aria")
        XCTAssertEqual(result, "hello-world")
    }
}
