import XCTest
@testable import aria_capture

final class MeetingDetailLayoutTests: XCTestCase {

    func testIsWideBelowThreshold() {
        XCTAssertFalse(MeetingDetailLayout.isWide(width: MeetingDetailLayout.wideThreshold - 1))
    }

    func testIsWideAtThreshold() {
        XCTAssertTrue(MeetingDetailLayout.isWide(width: MeetingDetailLayout.wideThreshold))
    }

    func testIsWideAboveThreshold() {
        XCTAssertTrue(MeetingDetailLayout.isWide(width: MeetingDetailLayout.wideThreshold + 200))
    }

    func testIsWideNarrowPhoneLikeWidth() {
        XCTAssertFalse(MeetingDetailLayout.isWide(width: 420))
    }
}

final class MeetingNoteMarkdownTests: XCTestCase {

    func testSummaryOnlyStripsTranscriptCallout() {
        let full = """
        ---
        titulo: "Reunión"
        ---

        ## Resumen
        Cerramos el sprint.


        > [!note]- Transcript
        > [00:00] Yo: hola
        """
        let summary = MeetingNoteMarkdown.summaryOnly(full)
        XCTAssertTrue(summary.contains("Cerramos el sprint."))
        XCTAssertFalse(summary.contains("Transcript"))
        XCTAssertFalse(summary.contains("[00:00] Yo: hola"))
    }

    func testSummaryOnlyReturnsWholeStringWhenNoCallout() {
        let full = "## Resumen\nSin transcript adjunto."
        XCTAssertEqual(MeetingNoteMarkdown.summaryOnly(full), full)
    }
}
