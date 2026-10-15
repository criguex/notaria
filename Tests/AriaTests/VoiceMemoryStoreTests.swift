import XCTest
@testable import aria_capture

final class VoiceMemoryStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-voice-memory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func embedding(_ vector: [Float]) -> SpeakerEmbedding {
        SpeakerEmbedding(vector: vector)
    }

    func testEmptyStoreHasNoProfilesOrMatches() throws {
        let store = try VoiceMemoryStore(fileURL: tempDir.appendingPathComponent("voice-memory.json"))
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertNil(store.match(embedding([1, 0, 0])))
    }

    func testUpsertPersistsAcrossInstancesEncryptedOnDisk() throws {
        let fileURL = tempDir.appendingPathComponent("voice-memory.json")
        let store = try VoiceMemoryStore(fileURL: fileURL)
        try store.upsert(name: "Ana", embedding: embedding([1, 0, 0]))

        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(raw.contains("Ana"))

        let reloaded = try VoiceMemoryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.load().map(\.name), ["Ana"])
    }

    func testUpsertReplacesExistingProfileCaseInsensitively() throws {
        let store = try VoiceMemoryStore(fileURL: tempDir.appendingPathComponent("voice-memory.json"))
        try store.upsert(name: "Ana", embedding: embedding([1, 0, 0]))
        try store.upsert(name: "ana", embedding: embedding([0, 1, 0]))
        let profiles = store.load()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.embedding.vector, [0, 1, 0])
    }

    func testUpsertIgnoresBlankName() throws {
        let store = try VoiceMemoryStore(fileURL: tempDir.appendingPathComponent("voice-memory.json"))
        try store.upsert(name: "   ", embedding: embedding([1, 0, 0]))
        XCTAssertTrue(store.load().isEmpty)
    }

    func testDeleteRemovesProfile() throws {
        let store = try VoiceMemoryStore(fileURL: tempDir.appendingPathComponent("voice-memory.json"))
        try store.upsert(name: "Ana", embedding: embedding([1, 0, 0]))
        try store.delete(name: "Ana")
        XCTAssertTrue(store.load().isEmpty)
    }

    func testMatchReturnsBestAboveThresholdOnly() throws {
        let store = try VoiceMemoryStore(fileURL: tempDir.appendingPathComponent("voice-memory.json"))
        try store.upsert(name: "Ana", embedding: embedding([1, 0, 0]))
        try store.upsert(name: "Luis", embedding: embedding([0, 1, 0]))

        let strongMatch = store.match(embedding([0.99, 0.01, 0]))
        XCTAssertEqual(strongMatch?.name, "Ana")

        let noMatch = store.match(embedding([0.5, 0.5, 0.7]))
        XCTAssertNil(noMatch)
    }

    func testBestMatchPureFunctionMirrorsInstanceMethod() {
        let profiles = [
            VoiceProfile(name: "Ana", embedding: embedding([1, 0, 0]), updatedAt: Date()),
            VoiceProfile(name: "Luis", embedding: embedding([0, 1, 0]), updatedAt: Date())
        ]
        let match = VoiceMemoryStore.bestMatch(embedding([0, 0.98, 0.02]), in: profiles)
        XCTAssertEqual(match?.name, "Luis")
    }
}
