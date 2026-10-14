import XCTest
@testable import aria_capture

final class PauseTraceabilityTests: XCTestCase {

    // MARK: - PauseLog

    func testPauseLogRecordsClosedIntervalOnEnd() {
        var log = PauseLog()
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 1_240)
        log.beginPause(at: start, activeOffsetSeconds: 42)
        XCTAssertTrue(log.isOpen)
        XCTAssertEqual(log.openPauseStart, start)

        let closed = log.endPause(at: end)
        XCTAssertEqual(closed?.start, start)
        XCTAssertEqual(closed?.end, end)
        XCTAssertEqual(closed?.transcriptOffsetSeconds, 42)
        XCTAssertFalse(log.isOpen)
        XCTAssertEqual(log.intervals.count, 1)
        XCTAssertEqual(log.totalPausedSeconds, 240, accuracy: 0.001)
    }

    func testPauseLogBeginIsIdempotentWhileOpen() {
        var log = PauseLog()
        log.beginPause(at: Date(timeIntervalSince1970: 0), activeOffsetSeconds: 10)
        log.beginPause(at: Date(timeIntervalSince1970: 500), activeOffsetSeconds: 999)
        XCTAssertEqual(log.openPauseStart, Date(timeIntervalSince1970: 0))
    }

    func testPauseLogEndWithoutOpenIsNoop() {
        var log = PauseLog()
        XCTAssertNil(log.endPause(at: Date()))
        XCTAssertTrue(log.intervals.isEmpty)
    }

    func testPauseLogResetClearsEverything() {
        var log = PauseLog()
        log.beginPause(at: Date(timeIntervalSince1970: 0), activeOffsetSeconds: 1)
        _ = log.endPause(at: Date(timeIntervalSince1970: 60))
        log.beginPause(at: Date(timeIntervalSince1970: 100), activeOffsetSeconds: 5)
        log.reset()
        XCTAssertTrue(log.intervals.isEmpty)
        XCTAssertFalse(log.isOpen)
        XCTAssertNil(log.openPauseStart)
    }

    func testMultiplePausesAccumulateTotal() {
        var log = PauseLog()
        log.beginPause(at: Date(timeIntervalSince1970: 0), activeOffsetSeconds: 10)
        _ = log.endPause(at: Date(timeIntervalSince1970: 60))
        log.beginPause(at: Date(timeIntervalSince1970: 200), activeOffsetSeconds: 80)
        _ = log.endPause(at: Date(timeIntervalSince1970: 320))
        XCTAssertEqual(log.intervals.count, 2)
        XCTAssertEqual(log.totalPausedSeconds, 180, accuracy: 0.001)
    }

    // MARK: - PauseLogic: formato y cálculo de duración real

    private func interval(startEpoch: TimeInterval, endEpoch: TimeInterval, offset: TimeInterval) -> PauseInterval {
        PauseInterval(
            start: Date(timeIntervalSince1970: startEpoch),
            end: Date(timeIntervalSince1970: endEpoch),
            transcriptOffsetSeconds: offset
        )
    }

    func testRangeLabelFormatsClockTimesAndMinutes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 14, minute: 32))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 14, minute: 36))!
        let pause = PauseInterval(start: start, end: end, transcriptOffsetSeconds: 300)
        let label = PauseLogic.rangeLabel(for: pause)
        XCTAssertTrue(label.hasSuffix("(4 min)"), label)
        XCTAssertTrue(label.contains("–"))
    }

    func testMarkerIncludesPrefixAndRange() {
        let pause = interval(startEpoch: 0, endEpoch: 120, offset: 30)
        let marker = PauseLogic.marker(for: pause)
        XCTAssertTrue(marker.hasPrefix(PauseLogic.markerPrefix))
        XCTAssertTrue(marker.contains(PauseLogic.rangeLabel(for: pause)))
    }

    func testRangeLabelRoundsUpToAtLeastOneMinute() {
        let pause = interval(startEpoch: 0, endEpoch: 20, offset: 0)
        XCTAssertTrue(PauseLogic.rangeLabel(for: pause).hasSuffix("(1 min)"))
    }

    func testWallClockSecondsAddsRecordedAndPaused() {
        let pauses = [interval(startEpoch: 0, endEpoch: 60, offset: 10), interval(startEpoch: 200, endEpoch: 260, offset: 50)]
        XCTAssertEqual(PauseLogic.wallClockSeconds(recordedSeconds: 600, pauses: pauses), 720, accuracy: 0.001)
        XCTAssertEqual(PauseLogic.totalPausedSeconds(pauses), 120, accuracy: 0.001)
    }

    func testWallClockSecondsWithNoPausesEqualsRecorded() {
        XCTAssertEqual(PauseLogic.wallClockSeconds(recordedSeconds: 300, pauses: []), 300, accuracy: 0.001)
    }

    // MARK: - PauseLogic: sección en el cuerpo de la nota

    func testAppendingPausesSectionAddsBulletsWhenNonEmpty() {
        let pause = interval(startEpoch: 0, endEpoch: 120, offset: 30)
        let result = PauseLogic.appendingPausesSection(to: "# Nota\n\nCuerpo.", pauses: [pause])
        XCTAssertTrue(result.contains(PauseLogic.sectionHeading))
        XCTAssertTrue(result.contains(PauseLogic.rangeLabel(for: pause)))
    }

    func testAppendingPausesSectionIsNoopWhenEmpty() {
        let markdown = "# Nota\n\nCuerpo."
        XCTAssertEqual(PauseLogic.appendingPausesSection(to: markdown, pauses: []), markdown)
    }

    func testAppendingPausesSectionDoesNotDuplicateHeading() {
        let pause = interval(startEpoch: 0, endEpoch: 60, offset: 5)
        let base = "# Nota\n\n\(PauseLogic.sectionHeading)\nya existe"
        let result = PauseLogic.appendingPausesSection(to: base, pauses: [pause])
        XCTAssertEqual(result, base.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - TranscriptFormatter: inserción de marcadores en el punto correcto

    func testRenderWithPausesInsertsMarkerBetweenSegments() {
        let segments = [
            TranscriptSegment(start: 0, end: 5, text: "antes", speaker: "Yo"),
            TranscriptSegment(start: 30, end: 35, text: "despues", speaker: "Yo")
        ]
        let pause = interval(startEpoch: 1_000, endEpoch: 1_240, offset: 10)
        let rendered = TranscriptFormatter.render(segments, pauses: [pause])
        let lines = rendered.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("antes"))
        XCTAssertTrue(lines[1].hasPrefix(PauseLogic.markerPrefix))
        XCTAssertTrue(lines[2].contains("despues"))
    }

    func testRenderWithPausesHandlesTieByPlacingPauseFirst() {
        let segments = [TranscriptSegment(start: 10, end: 12, text: "justo despues", speaker: "Yo")]
        let pause = interval(startEpoch: 0, endEpoch: 60, offset: 10)
        let rendered = TranscriptFormatter.render(segments, pauses: [pause])
        let lines = rendered.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasPrefix(PauseLogic.markerPrefix))
        XCTAssertTrue(lines[1].contains("justo despues"))
    }

    func testRenderWithoutPausesMatchesPlainRender() {
        let segments = [TranscriptSegment(start: 0, end: 1, text: "hola", speaker: "Yo")]
        XCTAssertEqual(TranscriptFormatter.render(segments, pauses: []), TranscriptFormatter.render(segments))
    }

    func testRenderWithMultiplePausesOrdersAllByOffset() {
        let segments = [
            TranscriptSegment(start: 0, end: 2, text: "uno", speaker: "Yo"),
            TranscriptSegment(start: 20, end: 22, text: "dos", speaker: "Yo"),
            TranscriptSegment(start: 40, end: 42, text: "tres", speaker: "Yo")
        ]
        let pauses = [
            interval(startEpoch: 0, endEpoch: 60, offset: 30),
            interval(startEpoch: 200, endEpoch: 260, offset: 10)
        ]
        let rendered = TranscriptFormatter.render(segments, pauses: pauses)
        let lines = rendered.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 5)
        XCTAssertTrue(lines[0].contains("uno"))
        XCTAssertTrue(lines[1].hasPrefix(PauseLogic.markerPrefix))
        XCTAssertTrue(lines[2].contains("dos"))
        XCTAssertTrue(lines[3].hasPrefix(PauseLogic.markerPrefix))
        XCTAssertTrue(lines[4].contains("tres"))
    }

    // MARK: - MeetingStore: persistencia de pausas

    func testMeetingStorePersistsAndReadsPauses() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-pause-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let pauses = [interval(startEpoch: 10, endEpoch: 70, offset: 5), interval(startEpoch: 500, endEpoch: 560, offset: 90)]
        let meetingID = try store.saveMeeting(
            date: Date(), title: "Con pausas", durationSeconds: 300,
            notePath: "/tmp/con-pausas.md", wavPath: nil,
            segments: [], quickNotes: [], pauses: pauses
        )

        let fetched = try store.pauses(meetingID: meetingID)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched[0].transcriptOffsetSeconds, 5, accuracy: 0.001)
        XCTAssertEqual(fetched[1].transcriptOffsetSeconds, 90, accuracy: 0.001)
        XCTAssertEqual(fetched[0].durationSeconds, 60, accuracy: 0.001)
    }

    func testMeetingStoreWithoutPausesReturnsEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-pause-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let meetingID = try store.saveMeeting(
            date: Date(), title: "Sin pausas", durationSeconds: 60,
            notePath: "/tmp/sin-pausas.md", wavPath: nil, segments: [], quickNotes: []
        )
        XCTAssertTrue(try store.pauses(meetingID: meetingID).isEmpty)
    }

    func testMeetingStorePurgeRemovesPausesOfOldMeetings() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-pause-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let pauses = [interval(startEpoch: 10, endEpoch: 70, offset: 5)]
        let oldMeetingID = try store.saveMeeting(
            date: Date(timeIntervalSinceNow: -40 * 86_400), title: "Vieja", durationSeconds: 60,
            notePath: "/tmp/vieja.md", wavPath: nil, segments: [], quickNotes: [], pauses: pauses
        )
        _ = try store.purge(olderThanDays: 30)
        XCTAssertTrue(try store.pauses(meetingID: oldMeetingID).isEmpty)
    }

    // MARK: - ObsidianWriter: frontmatter `pausas:`

    func testObsidianWriterIncludesPausasFrontmatter() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-pause-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let writer = ObsidianWriter(directory: tempDir)
        let pause = interval(startEpoch: 0, endEpoch: 120, offset: 30)
        let note = MeetingNote(
            title: "Con pausa", date: Date(), participants: [], durationSeconds: 300,
            body: "## Pausas\n- ⏸ test", transcript: nil, pauses: [pause]
        )
        let url = try writer.write(note)
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("pausas: [\"\(PauseLogic.rangeLabel(for: pause))\"]"))
    }

    func testObsidianWriterOmitsPausasLineWhenEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-pause-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let writer = ObsidianWriter(directory: tempDir)
        let note = MeetingNote(title: "Sin pausa", date: Date(), participants: [], durationSeconds: 60, body: "cuerpo", transcript: nil)
        let url = try writer.write(note)
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(content.contains("pausas:"))
    }
}
