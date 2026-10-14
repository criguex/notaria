import XCTest
@testable import aria_capture

final class ChatLogicTests: XCTestCase {

    private func context(
        id: Int64,
        title: String,
        date: TimeInterval = 1_754_600_000,
        transcript: String = "[00:00] Yo: Hola.",
        notes: [QuickNote] = []
    ) -> ChatMeetingContext {
        ChatMeetingContext(
            record: MeetingRecord(
                id: id,
                date: Date(timeIntervalSince1970: date),
                title: title,
                durationSeconds: 600,
                notePath: "/tmp/nota.md",
                wavPath: nil
            ),
            transcript: transcript,
            notes: notes
        )
    }

    func testRenderMeetingIncludesTitleNotesAndTranscript() {
        let block = MeetingChat.renderMeeting(context(
            id: 1,
            title: "Sync semanal",
            transcript: "[00:00] Otros: Falta la regresión.",
            notes: [QuickNote(timestamp: "10:02", text: "revisar QA"), QuickNote(timestamp: "", text: "sin hora")]
        ))
        XCTAssertTrue(block.contains("Sync semanal"))
        XCTAssertTrue(block.contains("(10 min)"))
        XCTAssertTrue(block.contains("- [10:02] revisar QA"))
        XCTAssertTrue(block.contains("- sin hora"))
        XCTAssertTrue(block.contains("[00:00] Otros: Falta la regresión."))
    }

    func testRenderMeetingMarksEmptyAndTruncatedTranscripts() {
        XCTAssertTrue(MeetingChat.renderMeeting(context(id: 1, title: "Vacía", transcript: ""))
            .contains("(sin voz detectada)"))
        let long = String(repeating: "a", count: MeetingChat.maxTranscriptChars + 500)
        let block = MeetingChat.renderMeeting(context(id: 2, title: "Larga", transcript: long))
        XCTAssertTrue(block.contains("… (transcript recortado)"))
        XCTAssertLessThan(block.count, long.count)
    }

    func testRenderContextChronologicalOrderAndAllIncluded() {
        let recent = context(id: 2, title: "Reciente", date: 2_000_000)
        let old = context(id: 1, title: "Antigua", date: 1_000_000)
        let rendered = MeetingChat.renderContext([recent, old])
        XCTAssertEqual(rendered.included, 2)
        XCTAssertEqual(rendered.omitted, 0)
        let oldIndex = rendered.text.range(of: "Antigua")!.lowerBound
        let recentIndex = rendered.text.range(of: "Reciente")!.lowerBound
        XCTAssertLessThan(oldIndex, recentIndex)
    }

    func testRenderContextBudgetDropsOldestAndCountsOmitted() {
        let filler = String(repeating: "x", count: 400)
        let meetings = (0..<5).map { index in
            context(id: Int64(5 - index), title: "R\(5 - index)", date: Double(5 - index) * 1_000, transcript: filler)
        }
        let rendered = MeetingChat.renderContext(meetings, budget: 1_000)
        XCTAssertEqual(rendered.included, 2)
        XCTAssertEqual(rendered.omitted, 3)
        XCTAssertTrue(rendered.text.contains("R5"))
        XCTAssertTrue(rendered.text.contains("R4"))
        XCTAssertFalse(rendered.text.contains("R3"))
        XCTAssertFalse(rendered.text.contains("R1"))
    }

    func testRenderContextAlwaysIncludesMostRecentEvenOverBudget() {
        let huge = context(id: 1, title: "Enorme", transcript: String(repeating: "x", count: 5_000))
        let rendered = MeetingChat.renderContext([huge], budget: 100)
        XCTAssertEqual(rendered.included, 1)
        XCTAssertEqual(rendered.omitted, 0)
    }

    func testUserMessageContainsContextAndQuestion() {
        let message = MeetingChat.userMessage(question: "¿qué prometí?", context: "### Reunión X")
        XCTAssertTrue(message.contains("## Contexto de reuniones"))
        XCTAssertTrue(message.contains("### Reunión X"))
        XCTAssertTrue(message.contains("## Pregunta\n¿qué prometí?"))
    }
}
