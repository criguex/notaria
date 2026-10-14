import XCTest
@testable import aria_capture

final class TranscriptLogicTests: XCTestCase {

    func testCoalescedMergesSameSpeakerShortGap() {
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "Hola, soy Aria.", speaker: "Yo"),
            TranscriptSegment(start: 5.5, end: 8, text: "Sigo hablando.", speaker: "Yo")
        ]
        let result = ChunkedTranscriber.coalesced(segments)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Hola, soy Aria. Sigo hablando.")
        XCTAssertEqual(result[0].end, 8)
    }

    func testCoalescedKeepsLongGapsSeparate() {
        let segments = [
            TranscriptSegment(start: 0, end: 3, text: "Primera.", speaker: "Yo"),
            TranscriptSegment(start: 10, end: 12, text: "Segunda.", speaker: "Yo")
        ]
        XCTAssertEqual(ChunkedTranscriber.coalesced(segments).count, 2)
    }

    func testCoalescedKeepsSpeakerTurnsSeparate() {
        let segments = [
            TranscriptSegment(start: 0, end: 3, text: "Pregunta.", speaker: "Yo"),
            TranscriptSegment(start: 3.2, end: 6, text: "Respuesta.", speaker: "Otros")
        ]
        XCTAssertEqual(ChunkedTranscriber.coalesced(segments).count, 2)
    }

    func testJoinedTurnTextHandlesHyphenBreak() {
        XCTAssertEqual(ChunkedTranscriber.joinedTurnText("transcrip-", "ción local"), "transcripción local")
        XCTAssertEqual(ChunkedTranscriber.joinedTurnText("hola", "mundo"), "hola mundo")
    }

    func testIsHallucinationByBlocklist() {
        XCTAssertTrue(ChunkedTranscriber.isHallucination(text: "Subtítulos por la comunidad de Amara.org", duration: 3))
        XCTAssertTrue(ChunkedTranscriber.isHallucination(text: "¡Suscríbete al canal!", duration: 2))
        XCTAssertFalse(ChunkedTranscriber.isHallucination(text: "Cerramos el sprint el viernes.", duration: 3))
    }

    func testIsHallucinationByWordRate() {
        let fast = Array(repeating: "palabra", count: 30).joined(separator: " ")
        XCTAssertTrue(ChunkedTranscriber.isHallucination(text: fast, duration: 1))
        XCTAssertFalse(ChunkedTranscriber.isHallucination(text: "tres palabras justas", duration: 1))
    }

    func testIsNonSpeech() {
        XCTAssertTrue(ChunkedTranscriber.isNonSpeech("[MÚSICA]"))
        XCTAssertTrue(ChunkedTranscriber.isNonSpeech("(aplausos)"))
        XCTAssertFalse(ChunkedTranscriber.isNonSpeech("Hola [según el acta] seguimos"))
    }

    func testStrippingOverlapPrefix() {
        let stripped = ChunkedTranscriber.strippingOverlapPrefix(
            "el viernes. Perfecto, cerramos entonces",
            previous: "Nos falta la regresión, la termino el viernes."
        )
        XCTAssertEqual(stripped, "Perfecto, cerramos entonces")
    }

    func testVoicedRegionsDetectsSpeechAndSkipsSilence() {
        let sampleRate = 16_000
        var samples = [Float](repeating: 0, count: sampleRate * 10)
        for index in (2 * sampleRate)..<(4 * sampleRate) {
            samples[index] = sinf(Float(index) * 0.1) * 0.3
        }
        let regions = ChunkedTranscriber.voicedRegions(
            in: samples, options: ChunkingOptions(), sampleRate: 16_000
        )
        XCTAssertEqual(regions.count, 1)
        let start = Double(regions[0].lowerBound) / Double(sampleRate)
        let end = Double(regions[0].upperBound) / Double(sampleRate)
        XCTAssertEqual(start, 2.0, accuracy: 0.5)
        XCTAssertEqual(end, 4.0, accuracy: 0.5)
    }

    func testTranscriptFormatter() {
        let segment = TranscriptSegment(start: 65, end: 70, text: "Hola", speaker: "Yo")
        XCTAssertEqual(TranscriptFormatter.timestamp(65), "01:05")
        XCTAssertEqual(TranscriptFormatter.timestamp(3_725), "1:02:05")
        XCTAssertEqual(TranscriptFormatter.line(segment), "[01:05] Yo: Hola")
    }

    func testExtractTitle() {
        XCTAssertEqual(MeetingEnhancer.extractTitle(from: "# Sync semanal\n\ncuerpo"), "Sync semanal")
        XCTAssertNil(MeetingEnhancer.extractTitle(from: "sin encabezado"))
    }
}

