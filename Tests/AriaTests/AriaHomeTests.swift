import XCTest
@testable import aria_capture

final class AriaHomeTests: XCTestCase {

    private var originalHome: String?

    override func setUpWithError() throws {
        originalHome = ProcessInfo.processInfo.environment["HOME"]
    }

    override func tearDownWithError() throws {
        if let originalHome {
            setenv("HOME", originalHome, 1)
        } else {
            unsetenv("HOME")
        }
    }

    func testAriaHomeRespectsHOMEEnvironmentOverride() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-home-tests-\(UUID().uuidString)", isDirectory: true)
        setenv("HOME", sandbox.path, 1)

        XCTAssertEqual(AriaHome.directory.path, sandbox.path)
        XCTAssertEqual(
            AriaHome.applicationSupportDirectory.path,
            sandbox.appendingPathComponent("Library/Application Support", isDirectory: true).path
        )
        XCTAssertEqual(
            AriaConfig.fileURL.path,
            sandbox.appendingPathComponent("Library/Application Support/Aria/config.json").path
        )
        XCTAssertEqual(
            WhisperModelStore.modelsDirectory.path,
            sandbox.appendingPathComponent("Library/Application Support/Aria/models", isDirectory: true).path
        )
        XCTAssertEqual(
            VoiceMemoryStore.defaultFileURL.path,
            sandbox.appendingPathComponent("Library/Application Support/Aria/voice-memory.json").path
        )
    }

    func testAriaHomeFallsBackToRealHomeWhenHOMEIsUnset() throws {
        unsetenv("HOME")
        XCTAssertEqual(AriaHome.directory.path, FileManager.default.homeDirectoryForCurrentUser.path)
    }
}
