import XCTest
@testable import aria_capture

final class SpeakerMapTests: XCTestCase {

    func testParseTrimsAndLowercasesLabels() throws {
        let map = try SpeakerMap.parse(" Otros = Juan Pérez , Yo=Ana GÃ³mez ")
        XCTAssertEqual(map, ["otros": "Juan Pérez", "yo": "Ana GÃ³mez"])
    }

    func testParseAllowsEqualsInName() throws {
        let map = try SpeakerMap.parse("Otros=Juan (a=b)")
        XCTAssertEqual(map, ["otros": "Juan (a=b)"])
    }

    func testParseRejectsMalformedPairs() {
        XCTAssertThrowsError(try SpeakerMap.parse("Otros"))
        XCTAssertThrowsError(try SpeakerMap.parse("=Juan"))
        XCTAssertThrowsError(try SpeakerMap.parse("Otros="))
        XCTAssertThrowsError(try SpeakerMap.parse(""))
        XCTAssertThrowsError(try SpeakerMap.parse("Otros=Juan,otros=Pedro"))
    }

    func testApplyRenamesSegmentsCaseInsensitively() throws {
        let map = try SpeakerMap.parse("otros=Juan")
        let segments = [
            TranscriptSegment(start: 0, end: 3, text: "Hola.", speaker: "Yo"),
            TranscriptSegment(start: 3, end: 6, text: "Buenas.", speaker: "Otros")
        ]
        let mapped = SpeakerMap.apply(map, to: segments)
        XCTAssertEqual(mapped.map(\.speaker), ["Yo", "Juan"])
        XCTAssertEqual(mapped.map(\.text), segments.map(\.text))
        XCTAssertTrue(TranscriptFormatter.render(mapped).contains("Juan: Buenas."))
    }

    func testApplyRenamesSpeakerList() throws {
        let map = try SpeakerMap.parse("Otros=Juan,Yo=Ana")
        XCTAssertEqual(SpeakerMap.apply(map, to: ["Yo", "Otros"]), ["Ana", "Juan"])
        XCTAssertEqual(SpeakerMap.apply(map, to: ["Desconocido"]), ["Desconocido"])
    }
}
