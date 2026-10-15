import XCTest
@testable import aria_capture

final class SpeakerDiarizerTests: XCTestCase {

    private let sampleRate: Double = 16_000

    /// Fundamental + un segundo tono ("formante") que distingue el timbre entre voces que
    /// pueden compartir el mismo pitch — un tono puro no tiene estructura de formantes real.
    private func voice(pitch: Double, formant: Double, seconds: Double) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            return Float(0.5 * sin(2 * Double.pi * pitch * t) + 0.3 * sin(2 * Double.pi * formant * t))
        }
    }

    private struct Plan {
        let speaker: String
        let pitch: Double
        let formant: Double
        let start: Double
        let duration: Double
    }

    private func channel(_ plan: [Plan], totalSeconds: Double) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(totalSeconds * sampleRate))
        for item in plan {
            let tonal = voice(pitch: item.pitch, formant: item.formant, seconds: item.duration)
            let startIndex = Int(item.start * sampleRate)
            for (offset, value) in tonal.enumerated() where startIndex + offset < samples.count {
                samples[startIndex + offset] = value
            }
        }
        return samples
    }

    private func makeSegments(for plan: [Plan]) -> [TranscriptSegment] {
        plan.map { TranscriptSegment(start: $0.start, end: $0.start + $0.duration, text: "hola", speaker: $0.speaker) }
    }

    func testTwoAlternatingVoicesAreSeparatedIntoTwoLabels() {
        let plan = [
            Plan(speaker: "Otros", pitch: 110, formant: 700, start: 0, duration: 2),
            Plan(speaker: "Otros", pitch: 110, formant: 1_800, start: 2.2, duration: 2),
            Plan(speaker: "Otros", pitch: 110, formant: 700, start: 4.4, duration: 2),
            Plan(speaker: "Otros", pitch: 110, formant: 1_800, start: 6.6, duration: 2)
        ]
        let samples = channel(plan, totalSeconds: 9)
        let segments = makeSegments(for: plan)

        let result = SpeakerDiarizer.relabel(segments: segments, originalSpeaker: "Otros", channelSamples: samples, sampleRate: sampleRate)

        XCTAssertEqual(result.speakerCount, 2)
        XCTAssertEqual(result.segments[0].speaker, result.segments[2].speaker)
        XCTAssertEqual(result.segments[1].speaker, result.segments[3].speaker)
        XCTAssertNotEqual(result.segments[0].speaker, result.segments[1].speaker)
        XCTAssertEqual(Set(result.segments.map(\.speaker)), ["Hablante 1", "Hablante 2"])
        XCTAssertEqual(result.embeddings.keys.sorted(), ["Hablante 1", "Hablante 2"])
    }

    func testSingleVoiceFallsBackToOriginalLabel() {
        let plan = [
            Plan(speaker: "Otros", pitch: 150, formant: 900, start: 0, duration: 2),
            Plan(speaker: "Otros", pitch: 150, formant: 900, start: 2.2, duration: 2),
            Plan(speaker: "Otros", pitch: 150, formant: 900, start: 4.4, duration: 2)
        ]
        let samples = channel(plan, totalSeconds: 7)
        let segments = makeSegments(for: plan)

        let result = SpeakerDiarizer.relabel(segments: segments, originalSpeaker: "Otros", channelSamples: samples, sampleRate: sampleRate)

        XCTAssertEqual(result.speakerCount, 1)
        XCTAssertTrue(result.segments.allSatisfy { $0.speaker == "Otros" })
        XCTAssertTrue(result.embeddings.isEmpty)
    }

    func testTooFewSegmentsFallsBackWithoutCrashing() {
        let segments = [TranscriptSegment(start: 0, end: 2, text: "hola", speaker: "Otros")]
        let samples = [Float](repeating: 0.1, count: Int(2 * sampleRate))
        let result = SpeakerDiarizer.relabel(segments: segments, originalSpeaker: "Otros", channelSamples: samples, sampleRate: sampleRate)
        XCTAssertEqual(result.segments, segments)
        XCTAssertEqual(result.speakerCount, 1)
    }

    func testMicChannelSegmentsAreIgnored() {
        let segments = [
            TranscriptSegment(start: 0, end: 2, text: "hola", speaker: "Yo"),
            TranscriptSegment(start: 2, end: 4, text: "hola", speaker: "Yo")
        ]
        let samples = [Float](repeating: 0.1, count: Int(4 * sampleRate))
        let result = SpeakerDiarizer.relabel(segments: segments, originalSpeaker: "Otros", channelSamples: samples, sampleRate: sampleRate)
        XCTAssertEqual(result.segments, segments)
        XCTAssertEqual(result.speakerCount, 0)
    }

    func testVeryShortLeftoverSegmentInheritsNearestClusterLabel() {
        let plan = [
            Plan(speaker: "Otros", pitch: 110, formant: 700, start: 0, duration: 0.2),
            Plan(speaker: "Otros", pitch: 110, formant: 700, start: 0.4, duration: 2),
            Plan(speaker: "Otros", pitch: 110, formant: 1_800, start: 2.6, duration: 2)
        ]
        let samples = channel(plan, totalSeconds: 5)
        let segments = makeSegments(for: plan)

        let result = SpeakerDiarizer.relabel(segments: segments, originalSpeaker: "Otros", channelSamples: samples, sampleRate: sampleRate)

        XCTAssertEqual(result.speakerCount, 2)
        XCTAssertEqual(result.segments[0].speaker, result.segments[1].speaker)
        XCTAssertNotEqual(result.segments[0].speaker, result.segments[2].speaker)
    }
}
