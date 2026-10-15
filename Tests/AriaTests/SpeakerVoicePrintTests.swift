import XCTest
@testable import aria_capture

final class SpeakerVoicePrintTests: XCTestCase {

    private let sampleRate: Double = 16_000

    private func sineWave(frequency: Double, seconds: Double, amplitude: Float = 0.5) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { i in
            amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    private func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * sampleRate))
    }

    func testEmbeddingIsNilForSilence() {
        let embedder = SpectralSpeakerEmbedder()
        XCTAssertNil(embedder.embedding(samples: silence(seconds: 1), sampleRate: sampleRate))
    }

    func testEmbeddingIsNilForTooShortSample() {
        let embedder = SpectralSpeakerEmbedder()
        XCTAssertNil(embedder.embedding(samples: sineWave(frequency: 150, seconds: 0.01), sampleRate: sampleRate))
    }

    func testEmbeddingIsNormalized() throws {
        let embedder = SpectralSpeakerEmbedder()
        let embedding = try XCTUnwrap(embedder.embedding(samples: sineWave(frequency: 150, seconds: 1.5), sampleRate: sampleRate))
        var normSquared: Float = 0
        for value in embedding.vector { normSquared += value * value }
        XCTAssertEqual(normSquared.squareRoot(), 1, accuracy: 0.01)
    }

    func testSameToneProducesHighSelfSimilarity() throws {
        let embedder = SpectralSpeakerEmbedder()
        let a = try XCTUnwrap(embedder.embedding(samples: sineWave(frequency: 150, seconds: 1.5), sampleRate: sampleRate))
        let b = try XCTUnwrap(embedder.embedding(samples: sineWave(frequency: 150, seconds: 1.5, amplitude: 0.3), sampleRate: sampleRate))
        XCTAssertGreaterThan(SpeakerEmbedding.cosineSimilarity(a, b), 0.95)
    }

    func testDistinctPitchesProduceLowerSimilarityThanSameTone() throws {
        let embedder = SpectralSpeakerEmbedder()
        let low = try XCTUnwrap(embedder.embedding(samples: sineWave(frequency: 120, seconds: 1.5), sampleRate: sampleRate))
        let low2 = try XCTUnwrap(embedder.embedding(samples: sineWave(frequency: 125, seconds: 1.5), sampleRate: sampleRate))
        let high = try XCTUnwrap(embedder.embedding(samples: sineWave(frequency: 280, seconds: 1.5), sampleRate: sampleRate))

        let sameSimilarity = SpeakerEmbedding.cosineSimilarity(low, low2)
        let crossSimilarity = SpeakerEmbedding.cosineSimilarity(low, high)
        XCTAssertGreaterThan(sameSimilarity, crossSimilarity)
    }

    func testPitchEstimateMatchesKnownFrequency() throws {
        let frame = sineWave(frequency: 200, seconds: 0.03)
        let pitch = try XCTUnwrap(SpectralSpeakerEmbedder.estimatePitch(frame: frame, sampleRate: sampleRate, minHz: 70, maxHz: 400))
        XCTAssertEqual(pitch, 200, accuracy: 15)
    }

    func testPitchEstimateNilForSilentFrame() {
        let frame = silence(seconds: 0.03)
        XCTAssertNil(SpectralSpeakerEmbedder.estimatePitch(frame: frame, sampleRate: sampleRate, minHz: 70, maxHz: 400))
    }

    func testReflectionCoefficientsNilForSilentFrame() {
        XCTAssertNil(SpectralSpeakerEmbedder.reflectionCoefficients(frame: silence(seconds: 0.03), order: 10))
    }

    func testReflectionCoefficientsHaveExpectedOrderBoundedAndFinite() throws {
        let frame = sineWave(frequency: 180, seconds: 0.03)
        let coefficients = try XCTUnwrap(SpectralSpeakerEmbedder.reflectionCoefficients(frame: frame, order: 10))
        XCTAssertEqual(coefficients.count, 10)
        XCTAssertTrue(coefficients.allSatisfy { $0.isFinite && abs($0) <= 1 })
    }

    func testReflectionCoefficientsStayFiniteAcrossManyFramesAndFrequencies() {
        for frequency in stride(from: 70.0, through: 1000.0, by: 23.0) {
            let frame = sineWave(frequency: frequency, seconds: 0.03)
            if let coefficients = SpectralSpeakerEmbedder.reflectionCoefficients(frame: frame, order: 10) {
                XCTAssertTrue(coefficients.allSatisfy(\.isFinite), "frecuencia \(frequency) produjo NaN/Inf")
            }
        }
    }

    func testCosineSimilarityHandlesMismatchedLengthsAndZeroVectors() {
        let a = SpeakerEmbedding(vector: [1, 0, 0])
        let b = SpeakerEmbedding(vector: [1, 0])
        XCTAssertEqual(SpeakerEmbedding.cosineSimilarity(a, b), 0)

        let zero = SpeakerEmbedding(vector: [0, 0, 0])
        XCTAssertEqual(SpeakerEmbedding.cosineSimilarity(zero, a), 0)
    }
}
