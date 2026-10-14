import XCTest
@testable import aria_capture

final class PolishTests: XCTestCase {

    private let segments = [
        TranscriptSegment(start: 0, end: 5, text: "ola necesitamos cerrar el spring", speaker: "Yo"),
        TranscriptSegment(start: 5, end: 9, text: "si el biernes lo cerramos", speaker: "Otros")
    ]

    func testParsedTextsRoundtrip() {
        let output = """
        [00:00] Yo: Hola, necesitamos cerrar el sprint.
        [00:05] Otros: Sí, el viernes lo cerramos.
        """
        XCTAssertEqual(
            TranscriptPolisher.parsedTexts(from: output, expectedCount: 2),
            ["Hola, necesitamos cerrar el sprint.", "Sí, el viernes lo cerramos."]
        )
    }

    func testParsedTextsRejectsCountMismatchAndPreambles() {
        XCTAssertNil(TranscriptPolisher.parsedTexts(from: "[00:00] Yo: solo una línea", expectedCount: 2))
        let withExtra = """
        Aquí está el transcript corregido:
        [00:00] Yo: Hola.
        [00:05] Otros: Adiós.
        """
        XCTAssertEqual(TranscriptPolisher.parsedTexts(from: withExtra, expectedCount: 2)?.count, 2)
        XCTAssertNil(TranscriptPolisher.parsedTexts(from: "texto sin formato", expectedCount: 1))
    }

    func testAppliedKeepsTimestampsAndSpeakers() {
        let polished = TranscriptPolisher.applied(
            texts: ["Hola, necesitamos cerrar el sprint.", "Sí, el viernes lo cerramos."],
            to: segments
        )
        XCTAssertEqual(polished.map(\.speaker), ["Yo", "Otros"])
        XCTAssertEqual(polished.map(\.start), [0, 5])
        XCTAssertEqual(polished.map(\.end), [5, 9])
        XCTAssertEqual(polished[0].text, "Hola, necesitamos cerrar el sprint.")
    }

    func testMessageIncludesCalendarAttendees() {
        let meeting = CalendarMeeting(
            title: "Sync",
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 100),
            attendees: ["Ana López"],
            isAllDay: false
        )
        let message = TranscriptPolisher.message(transcript: "[00:00] Yo: hola", meeting: meeting)
        XCTAssertTrue(message.contains("Ana López"))
        XCTAssertTrue(message.contains("## Transcript a corregir"))
        XCTAssertFalse(TranscriptPolisher.message(transcript: "x", meeting: nil).contains("Participantes"))
    }

    func testConfigValidatesTranscriptPolish() throws {
        var config = AriaConfig()
        XCTAssertFalse(config.transcriptPolish)
        try config.set(key: "transcriptPolish", value: "TRUE")
        XCTAssertTrue(config.transcriptPolish)
        XCTAssertThrowsError(try config.set(key: "transcriptPolish", value: "quizás"))
    }
}
