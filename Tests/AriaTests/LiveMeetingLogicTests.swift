import AVFoundation
import XCTest
@testable import aria_capture

final class LiveMeetingLogicTests: XCTestCase {

    // MARK: - LiveTranscriptFeed

    func testLiveTranscriptFeedOrdersAndLabelsBySpeaker() {
        let feed = LiveTranscriptFeed()
        feed.append([TranscriptSegment(start: 2, end: 3, text: "segunda")], speaker: LiveTranscriptFeed.themLabel)
        feed.append([TranscriptSegment(start: 0, end: 1, text: "primera")], speaker: LiveTranscriptFeed.youLabel)

        let lines = feed.recentLines(limit: 10)
        XCTAssertEqual(lines.map(\.text), ["primera", "segunda"])
        XCTAssertEqual(lines.map(\.speaker), [LiveTranscriptFeed.youLabel, LiveTranscriptFeed.themLabel])
        XCTAssertEqual(LiveTranscriptFeed.formatted(lines), "Tú: primera\nEllos: segunda")
    }

    func testLiveTranscriptFeedSkipsBlankSegmentsAndTrimsToMaxLines() {
        let feed = LiveTranscriptFeed(maxLines: 3)
        feed.append([TranscriptSegment(start: 0, end: 1, text: "   ")], speaker: LiveTranscriptFeed.youLabel)
        for index in 0..<5 {
            feed.append(
                [TranscriptSegment(start: Double(index), end: Double(index) + 1, text: "linea \(index)")],
                speaker: LiveTranscriptFeed.youLabel
            )
        }
        let lines = feed.recentLines(limit: 10)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines.map(\.text), ["linea 2", "linea 3", "linea 4"])
    }

    func testLiveTranscriptFeedRecentLinesRespectsLimitAndReset() {
        let feed = LiveTranscriptFeed()
        feed.append(
            [TranscriptSegment(start: 0, end: 1, text: "a"), TranscriptSegment(start: 1, end: 2, text: "b")],
            speaker: LiveTranscriptFeed.youLabel
        )
        XCTAssertEqual(feed.recentLines(limit: 1).map(\.text), ["b"])
        XCTAssertEqual(feed.recentLines(limit: 0), [])

        feed.reset()
        XCTAssertEqual(feed.recentLines(limit: 10), [])
    }

    // MARK: - MeetingPromptDecider

    private func meeting(_ title: String = "Daily") -> CalendarMeeting {
        CalendarMeeting(
            title: title,
            start: Date(timeIntervalSince1970: 1_800_000_000),
            end: Date(timeIntervalSince1970: 1_800_003_600),
            attendees: ["Ana"],
            isAllDay: false
        )
    }

    func testShouldPromptOnMicPlusCallAppWithoutCalendar() {
        XCTAssertTrue(MeetingPromptDecider.shouldPrompt(
            micInUse: true, callApps: ["Zoom"], meetingNow: nil, alwaysOn: false, isRecording: false
        ))
        XCTAssertFalse(MeetingPromptDecider.shouldPrompt(
            micInUse: true, callApps: [], meetingNow: nil, alwaysOn: false, isRecording: false
        ))
        XCTAssertFalse(MeetingPromptDecider.shouldPrompt(
            micInUse: false, callApps: ["Zoom"], meetingNow: nil, alwaysOn: false, isRecording: false
        ))
    }

    func testShouldPromptOnCalendarAloneWithoutCallApp() {
        XCTAssertTrue(MeetingPromptDecider.shouldPrompt(
            micInUse: false, callApps: [], meetingNow: meeting(), alwaysOn: false, isRecording: false
        ))
    }

    func testShouldPromptSuppressedByAlwaysOnOrRecording() {
        XCTAssertFalse(MeetingPromptDecider.shouldPrompt(
            micInUse: true, callApps: ["Zoom"], meetingNow: meeting(), alwaysOn: true, isRecording: false
        ))
        XCTAssertFalse(MeetingPromptDecider.shouldPrompt(
            micInUse: true, callApps: ["Zoom"], meetingNow: meeting(), alwaysOn: false, isRecording: true
        ))
    }

    func testPendingKeyDedupesSameSignalAndRenotifiesOnChange() {
        let first = MeetingPromptDecider.pendingKey(
            micInUse: false, callApps: [], meetingNow: meeting(), alwaysOn: false, isRecording: false, lastKey: nil
        )
        XCTAssertNotNil(first)
        XCTAssertNil(MeetingPromptDecider.pendingKey(
            micInUse: false, callApps: [], meetingNow: meeting(), alwaysOn: false, isRecording: false, lastKey: first
        ))

        var other = meeting("Otra")
        other.start = meeting().start.addingTimeInterval(3_600)
        XCTAssertNotEqual(
            MeetingPromptDecider.pendingKey(
                micInUse: false, callApps: [], meetingNow: other, alwaysOn: false, isRecording: false, lastKey: first
            ),
            first
        )
    }

    func testShouldPromptSuppressedByExcludedCalendar() {
        var excluded = meeting("Daily Exchange")
        excluded.promptExcluded = true
        XCTAssertFalse(MeetingPromptDecider.shouldPrompt(
            micInUse: true, callApps: ["Teams"], meetingNow: excluded, alwaysOn: false, isRecording: false
        ))
        XCTAssertFalse(MeetingPromptDecider.shouldPrompt(
            micInUse: false, callApps: [], meetingNow: excluded, alwaysOn: false, isRecording: false
        ))
    }

    func testUpdatedLastKeyResetsOnceSignalClearsSoRepeatedCallPrompts() {
        // Bug real: lastPromptKey nunca se soltaba cuando la señal desaparecía, así que
        // una segunda llamada de Teams sin evento de calendario asociado (misma key
        // "call:Teams") nunca volvía a avisar. updatedLastKey debe soltar el key en
        // cuanto no hay señal activa, para que la siguiente llamada sí dispare el aviso.
        let afterFirstCall = MeetingPromptDecider.pendingKey(
            micInUse: true, callApps: ["Teams"], meetingNow: nil, alwaysOn: false, isRecording: false, lastKey: nil
        )
        XCTAssertNotNil(afterFirstCall)

        XCTAssertNil(MeetingPromptDecider.pendingKey(
            micInUse: true, callApps: ["Teams"], meetingNow: nil, alwaysOn: false, isRecording: false, lastKey: afterFirstCall
        ))

        let clearedKey = MeetingPromptDecider.updatedLastKey(
            micInUse: false, callApps: [], meetingNow: nil, lastKey: afterFirstCall
        )
        XCTAssertNil(clearedKey)

        let secondCallKey = MeetingPromptDecider.pendingKey(
            micInUse: true, callApps: ["Teams"], meetingNow: nil, alwaysOn: false, isRecording: false, lastKey: clearedKey
        )
        XCTAssertNotNil(secondCallKey)
        XCTAssertEqual(secondCallKey, afterFirstCall)
    }

    func testUpdatedLastKeyKeepsDedupeWhileSignalStillActive() {
        let key = MeetingPromptDecider.pendingKey(
            micInUse: true, callApps: ["Zoom"], meetingNow: nil, alwaysOn: false, isRecording: false, lastKey: nil
        )
        XCTAssertNotNil(key)
        XCTAssertEqual(
            MeetingPromptDecider.updatedLastKey(micInUse: true, callApps: ["Zoom"], meetingNow: nil, lastKey: key),
            key
        )
    }

    func testDecisionClassifiesEachBranch() {
        XCTAssertEqual(
            MeetingPromptDecider.decision(
                micInUse: true, callApps: [], meetingNow: nil, alwaysOn: true, isRecording: false, hasConsent: true, lastKey: nil
            ),
            .autoStart
        )
        var excluded = meeting()
        excluded.promptExcluded = true
        XCTAssertEqual(
            MeetingPromptDecider.decision(
                micInUse: true, callApps: ["Teams"], meetingNow: excluded, alwaysOn: false, isRecording: false, hasConsent: true, lastKey: nil
            ),
            .excludedCalendar
        )
        XCTAssertEqual(
            MeetingPromptDecider.decision(
                micInUse: true, callApps: ["Teams"], meetingNow: nil, alwaysOn: false, isRecording: false, hasConsent: true, lastKey: nil
            ),
            .prompted
        )
        let dupeKey = MeetingPromptDecider.key(meetingNow: nil, callApps: ["Teams"])
        XCTAssertEqual(
            MeetingPromptDecider.decision(
                micInUse: true, callApps: ["Teams"], meetingNow: nil, alwaysOn: false, isRecording: false, hasConsent: true, lastKey: dupeKey
            ),
            .dedupedSameSignal
        )
        XCTAssertEqual(
            MeetingPromptDecider.decision(
                micInUse: false, callApps: [], meetingNow: nil, alwaysOn: false, isRecording: true, hasConsent: true, lastKey: nil
            ),
            .suppressedBusy
        )
        XCTAssertEqual(
            MeetingPromptDecider.decision(
                micInUse: false, callApps: [], meetingNow: nil, alwaysOn: false, isRecording: false, hasConsent: true, lastKey: nil
            ),
            .noSignal
        )
    }

    func testDetectorLogLineOmitsTitlesAndNamesIncludesSignalsAndDecision() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let line = DetectorLogFormatter.line(
            at: date,
            micInUse: true,
            callApps: ["Teams", "Zoom"],
            hasMeetingNow: true,
            meetingPromptExcluded: true,
            alwaysOn: false,
            isRecording: false,
            decision: MeetingPromptDecider.Decision.excludedCalendar.rawValue
        )
        XCTAssertTrue(line.contains("mic=true"))
        XCTAssertTrue(line.contains("apps=Teams+Zoom"))
        XCTAssertTrue(line.contains("meetingNow=true"))
        XCTAssertTrue(line.contains("meetingExcluded=true"))
        XCTAssertTrue(line.contains("decision=suppressed-excluded-calendar"))
        XCTAssertFalse(line.lowercased().contains("daily"))
        XCTAssertFalse(line.lowercased().contains("sync"))
    }

    func testDetectorLogWriterRotatesWhenOverLimit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("detector.log")
        let writer = DetectorLogWriter(url: url, maxBytes: 50)

        for index in 0..<10 {
            writer.append("linea de prueba numero \(index) con texto de relleno")
        }
        writer.flush()

        let rotated = dir.appendingPathComponent("detector.1.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testMeetingCardOffersRecordingByDefaultAndHidesItWhenExcluded() {
        var meeting = CalendarMeeting(
            title: "Daily", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100),
            attendees: [], isAllDay: false, videoLink: "https://meet.google.com/abc-defg-hij"
        )
        let openCard = MeetingCardBuilder.build(meeting: meeting, at: Date(timeIntervalSince1970: 0), nativeAppInstalled: false)
        XCTAssertTrue(openCard.offerRecording)

        meeting.promptExcluded = true
        let excludedCard = MeetingCardBuilder.build(meeting: meeting, at: Date(timeIntervalSince1970: 0), nativeAppInstalled: false)
        XCTAssertFalse(excludedCard.offerRecording)
        XCTAssertTrue(excludedCard.canJoin)
    }

    func testPromptTitleMentionsMeetingWhenAvailable() {
        XCTAssertEqual(MeetingPromptDecider.promptTitle(meetingNow: nil), "¿Tomar notas con NotarIA?")
        XCTAssertEqual(
            MeetingPromptDecider.promptTitle(meetingNow: meeting("Sync Q3")),
            "¿Tomar notas de \"Sync Q3\" con NotarIA?"
        )
    }

    func testTimeLabelFormatsHourMinuteInGivenTimeZone() {
        let date = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15T08:00:00Z
        XCTAssertEqual(MeetingPromptDecider.timeLabel(for: date, timeZone: TimeZone(identifier: "UTC")!), "08:00")
        XCTAssertEqual(
            MeetingPromptDecider.timeLabel(for: date, timeZone: TimeZone(identifier: "America/Bogota")!),
            "03:00"
        )
    }

    func testPlatformLabelRecognizesKnownDomainsAndRejectsUnknownOrMissing() {
        XCTAssertEqual(MeetingPromptDecider.platformLabel(videoLink: "https://meet.google.com/abc-defg-hij"), "Meet")
        XCTAssertEqual(MeetingPromptDecider.platformLabel(videoLink: "https://zoom.us/j/123456"), "Zoom")
        XCTAssertNil(MeetingPromptDecider.platformLabel(videoLink: "https://example.com/not-a-meeting"))
        XCTAssertNil(MeetingPromptDecider.platformLabel(videoLink: nil))
        XCTAssertNil(MeetingPromptDecider.platformLabel(videoLink: ""))
    }

    func testPromptSubtitleCombinesTimeAndPlatformOrFallsBackToJustTime() {
        var withLink = meeting("Sync Q3")
        withLink.videoLink = "https://meet.google.com/abc-defg-hij"
        XCTAssertEqual(
            MeetingPromptDecider.promptSubtitle(meetingNow: withLink, timeZone: TimeZone(identifier: "UTC")!),
            "08:00 · Meet"
        )

        let withoutLink = meeting("Sync Q3")
        XCTAssertEqual(
            MeetingPromptDecider.promptSubtitle(meetingNow: withoutLink, timeZone: TimeZone(identifier: "UTC")!),
            "08:00"
        )

        XCTAssertNil(MeetingPromptDecider.promptSubtitle(meetingNow: nil))
    }

    // MARK: - PillPosition

    func testPillPositionDecodeFallsBackToDefaultOnInvalidInput() {
        XCTAssertEqual(PillPosition.decode(nil), PillPosition.defaultPosition)
        XCTAssertEqual(PillPosition.decode("nope"), PillPosition.defaultPosition)
        XCTAssertEqual(PillPosition.decode("abc,10"), PillPosition.defaultPosition)
    }

    func testPillPositionEncodeDecodeRoundtrips() {
        let position = PillPosition(x: 120.5, y: 48)
        XCTAssertEqual(PillPosition.decode(position.encoded()), position)
    }

    func testPillPositionClampsToScreenBounds() {
        let offscreen = PillPosition(x: 5_000, y: -200)
        let clamped = offscreen.clamped(toScreenSize: CGSize(width: 1440, height: 900), pillSize: CGSize(width: 196, height: 180))
        XCTAssertEqual(clamped, PillPosition(x: 1244, y: 0))
    }

    func testPillPositionMovedAppliesDelta() {
        let moved = PillPosition(x: 10, y: 10).moved(byDx: 5, dy: -3)
        XCTAssertEqual(moved, PillPosition(x: 15, y: 7))
    }

    // MARK: - GrowableStereoRecorder incremental windows

    private func makeBuffer(seconds: Double, value: Float) -> AVAudioPCMBuffer {
        let sampleRate = 16_000.0
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        for index in 0..<Int(frameCount) {
            buffer.floatChannelData![0][index] = value
        }
        return buffer
    }

    func testGrowableRecorderNewSamplesReturnsOnlyUnseenAudio() {
        let recorder = GrowableStereoRecorder(maxSeconds: 10)
        recorder.begin(epochSeconds: 0)
        recorder.addMic(makeBuffer(seconds: 1, value: 0.1), atHostSeconds: 0)
        recorder.addSystem(makeBuffer(seconds: 1, value: 0.2), atHostSeconds: 0)

        let firstWindow = recorder.newSamples(micCursor: 0, systemCursor: 0)
        XCTAssertEqual(firstWindow.mic.count, 16_000)
        XCTAssertEqual(firstWindow.system.count, 16_000)
        XCTAssertEqual(firstWindow.micCursor, 16_000)
        XCTAssertEqual(firstWindow.systemCursor, 16_000)

        let emptyWindow = recorder.newSamples(micCursor: firstWindow.micCursor, systemCursor: firstWindow.systemCursor)
        XCTAssertTrue(emptyWindow.mic.isEmpty)
        XCTAssertTrue(emptyWindow.system.isEmpty)

        recorder.addMic(makeBuffer(seconds: 1, value: 0.3), atHostSeconds: 1)
        let secondWindow = recorder.newSamples(micCursor: firstWindow.micCursor, systemCursor: firstWindow.systemCursor)
        XCTAssertEqual(secondWindow.mic.count, 16_000)
        XCTAssertEqual(secondWindow.mic.first, 0.3)
        XCTAssertTrue(secondWindow.system.isEmpty)
    }
}
