import XCTest
@testable import aria_capture

final class MainWindowViewModelTests: XCTestCase {

    private func record(
        id: Int64,
        title: String,
        date: TimeInterval,
        source: String = "aria",
        externalID: String? = nil
    ) -> MeetingRecord {
        MeetingRecord(
            id: id,
            date: Date(timeIntervalSince1970: date),
            title: title,
            durationSeconds: 600,
            notePath: "/tmp/\(id).md",
            wavPath: nil,
            source: source,
            externalID: externalID
        )
    }

    func testFilteredBySourceNativeAndImported() {
        let records = [
            record(id: 1, title: "Nativa", date: 1_000, source: "aria"),
            record(id: 2, title: "Importada", date: 2_000, source: "granola", externalID: "g1")
        ]
        XCTAssertEqual(MeetingHistoryViewModel.filtered(records, source: .all).count, 2)
        XCTAssertEqual(MeetingHistoryViewModel.filtered(records, source: .native).map(\.id), [1])
        XCTAssertEqual(MeetingHistoryViewModel.filtered(records, source: .imported).map(\.id), [2])
    }

    func testGroupedByDaySortsDescendingAndKeepsOrderWithinDay() {
        let calendar = Calendar(identifier: .gregorian)
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!
        let day1Later = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 15))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9))!
        let records = [
            record(id: 1, title: "A", date: day1.timeIntervalSince1970),
            record(id: 2, title: "B", date: day1Later.timeIntervalSince1970),
            record(id: 3, title: "C", date: day2.timeIntervalSince1970)
        ]
        let sections = MeetingHistoryViewModel.grouped(records, calendar: calendar)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].records.map(\.id), [3])
        XCTAssertEqual(sections[1].records.map(\.id), [2, 1])
    }

    func testGroupedEmptyInput() {
        XCTAssertTrue(MeetingHistoryViewModel.grouped([]).isEmpty)
    }

    func testMeetingIDOrderFromHitsDeduplicatesPreservingFirstOccurrence() {
        let hits = [
            SearchHit(meetingID: 3, title: "C", date: Date(), kind: "transcript", speaker: "", snippet: ""),
            SearchHit(meetingID: 1, title: "A", date: Date(), kind: "nota", speaker: "", snippet: ""),
            SearchHit(meetingID: 3, title: "C", date: Date(), kind: "título", speaker: "", snippet: "")
        ]
        XCTAssertEqual(MeetingHistoryViewModel.meetingIDOrder(fromHits: hits), [3, 1])
    }

    func testVisibleRecordsWithoutSearchReturnsSourceFilteredOnly() {
        let records = [
            record(id: 1, title: "Nativa", date: 1_000, source: "aria"),
            record(id: 2, title: "Importada", date: 2_000, source: "granola", externalID: "g1")
        ]
        let visible = MeetingHistoryViewModel.visibleRecords(all: records, source: .native, searchHitsOrder: nil)
        XCTAssertEqual(visible.map(\.id), [1])
    }

    func testVisibleRecordsWithSearchOrdersBySearchAndRespectsSourceFilter() {
        let records = [
            record(id: 1, title: "Nativa", date: 1_000, source: "aria"),
            record(id: 2, title: "Importada", date: 2_000, source: "granola", externalID: "g1")
        ]
        let visible = MeetingHistoryViewModel.visibleRecords(all: records, source: .all, searchHitsOrder: [2, 1])
        XCTAssertEqual(visible.map(\.id), [2, 1])

        let visibleNativeOnly = MeetingHistoryViewModel.visibleRecords(all: records, source: .native, searchHitsOrder: [2, 1])
        XCTAssertEqual(visibleNativeOnly.map(\.id), [1])
    }

    func testChatSessionLogicTrimmedQuestion() {
        XCTAssertNil(ChatSessionLogic.trimmedQuestion("   "))
        XCTAssertEqual(ChatSessionLogic.trimmedQuestion("  ¿qué prometí?  "), "¿qué prometí?")
    }

    func testChatSessionLogicAppendingQuestion() {
        let turns = ChatSessionLogic.appendingQuestion([], question: "¿y ahora?")
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].question, "¿y ahora?")
        XCTAssertEqual(turns[0].answer, "")
    }

    func testChatSessionLogicAppendingChunkAccumulatesAndIgnoresOutOfRange() {
        var turns = ChatSessionLogic.appendingQuestion([], question: "q")
        turns = ChatSessionLogic.appendingChunk(turns, chunk: "Hola ", at: 0)
        turns = ChatSessionLogic.appendingChunk(turns, chunk: "mundo", at: 0)
        XCTAssertEqual(turns[0].answer, "Hola mundo")
        let unchanged = ChatSessionLogic.appendingChunk(turns, chunk: "x", at: 5)
        XCTAssertEqual(unchanged, turns)
    }

    func testChatSessionLogicMarkError() {
        var turns = ChatSessionLogic.appendingQuestion([], question: "q")
        turns = ChatSessionLogic.markError(turns, at: 0, message: "boom")
        XCTAssertTrue(turns[0].isError)
        XCTAssertEqual(turns[0].answer, "[error] boom")
    }
}
