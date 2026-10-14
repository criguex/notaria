import XCTest
import AVFoundation
@testable import aria_capture

final class SileroVADRuntimeTests: XCTestCase {

    private static let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("aria-silero-vad-tests", isDirectory: true)

    private func modelPathOrSkip() async throws -> String {
        try? FileManager.default.createDirectory(at: Self.tempRoot, withIntermediateDirectories: true)
        let destination = Self.tempRoot.appendingPathComponent(SileroModel.fileName)
        do {
            let url = try await SileroModel.ensureModel(destination: destination)
            return url.path
        } catch {
            throw XCTSkip("Modelo Silero VAD no disponible en esta sesión (sin red o descarga falló): \(error)")
        }
    }

    private func synthesizeSpeech(text: String) throws -> [Float] {
        let outputURL = Self.tempRoot.appendingPathComponent("speech-\(UUID().uuidString).caf")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", outputURL.path, "--data-format=LEF32@16000", text]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: outputURL.path) else {
            throw XCTSkip("'say' no sintetizó el fixture de voz en esta sesión")
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let file = try AVAudioFile(forReading: outputURL)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw XCTSkip("no se pudo preparar el buffer del fixture de voz")
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else {
            throw XCTSkip("fixture de voz sin canal float")
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private func silence(seconds: Double, sampleRate: Int = 16_000) -> [Float] {
        [Float](repeating: 0, count: Int(Double(sampleRate) * seconds))
    }

    private func toneBurst(seconds: Double, amplitude: Float = 0.3, sampleRate: Int = 16_000) -> [Float] {
        (0..<Int(Double(sampleRate) * seconds)).map { sinf(Float($0) * 0.1) * amplitude }
    }

    func testSileroVADInitSucceedsWithRealModelAndFailsWithoutIt() async throws {
        let modelPath = try await modelPathOrSkip()
        XCTAssertNotNil(SileroVAD(modelPath: modelPath))
        XCTAssertNil(SileroVAD(modelPath: modelPath + "-no-existe"))
    }

    func testSileroVADOnPureSilenceDetectsNoRegions() async throws {
        let modelPath = try await modelPathOrSkip()
        guard let vad = SileroVAD(modelPath: modelPath) else {
            XCTFail("modelo descargado pero SileroVAD no inicializó")
            return
        }
        let regions = vad.voicedRegions(in: silence(seconds: 3), sampleRate: 16_000)
        XCTAssertTrue(regions.isEmpty)
    }

    func testSileroVADOnSyntheticToneAndNoiseStaysWithinBoundsAndRejectsNonSpeech() async throws {
        let modelPath = try await modelPathOrSkip()
        guard let vad = SileroVAD(modelPath: modelPath) else {
            XCTFail("modelo descargado pero SileroVAD no inicializó")
            return
        }
        let noise: [Float] = (0..<(16_000 * 2)).map { _ in Float.random(in: -0.3...0.3) }
        let samples = silence(seconds: 1) + toneBurst(seconds: 2) + silence(seconds: 1) + noise + silence(seconds: 1)

        let regions = vad.voicedRegions(in: samples, sampleRate: 16_000)

        for region in regions {
            XCTAssertGreaterThanOrEqual(region.lowerBound, 0)
            XCTAssertLessThanOrEqual(region.upperBound, samples.count)
        }
        XCTAssertTrue(regions.isEmpty, "un tono puro y ruido blanco no deberían reconocerse como habla real")
    }

    func testSileroVADDetectsSpeechSegmentSynthesizedWithSay() async throws {
        let modelPath = try await modelPathOrSkip()
        guard let vad = SileroVAD(modelPath: modelPath) else {
            XCTFail("modelo descargado pero SileroVAD no inicializó")
            return
        }
        let speech = try synthesizeSpeech(text: "Hola, esta es una prueba sintetica de voz para validar Silero VAD en Aria.")
        let samples = silence(seconds: 1) + speech + silence(seconds: 1)

        let regions = vad.voicedRegions(in: samples, sampleRate: 16_000)

        XCTAssertFalse(regions.isEmpty, "Silero debería detectar la región con voz sintetizada")
        guard let region = regions.first else { return }
        let speechStart = 16_000
        let speechEnd = 16_000 + speech.count
        XCTAssertLessThan(region.lowerBound, speechEnd)
        XCTAssertGreaterThan(region.upperBound, speechStart)
    }

    func testSileroModelDownloadVerifiesSizeAndChecksum() async throws {
        let modelPath = try await modelPathOrSkip()
        let attrs = try FileManager.default.attributesOfItem(atPath: modelPath)
        let size = (attrs[.size] as? Int64) ?? -1
        XCTAssertEqual(size, SileroModel.expectedSizeBytes)
    }
}
