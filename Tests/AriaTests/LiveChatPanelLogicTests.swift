import XCTest
@testable import aria_capture

final class LiveChatPanelLogicTests: XCTestCase {

    // MARK: - ChatBubbleLogic: agrupación de mensajes

    func testGroupedMergesConsecutiveSameSpeakerLines() {
        let lines = [
            LiveTranscriptLine(speaker: LiveTranscriptFeed.youLabel, text: "hola", timestamp: 0),
            LiveTranscriptLine(speaker: LiveTranscriptFeed.youLabel, text: "como estas", timestamp: 2),
            LiveTranscriptLine(speaker: LiveTranscriptFeed.themLabel, text: "bien", timestamp: 4)
        ]
        let groups = ChatBubbleLogic.grouped(lines)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].messages.map(\.text), ["hola", "como estas"])
        XCTAssertTrue(groups[0].isYou)
        XCTAssertEqual(groups[1].messages.map(\.text), ["bien"])
        XCTAssertFalse(groups[1].isYou)
    }

    func testGroupedBreaksOnSpeakerAlternation() {
        let lines = [
            LiveTranscriptLine(speaker: LiveTranscriptFeed.youLabel, text: "a", timestamp: 0),
            LiveTranscriptLine(speaker: LiveTranscriptFeed.themLabel, text: "b", timestamp: 1),
            LiveTranscriptLine(speaker: LiveTranscriptFeed.youLabel, text: "c", timestamp: 2)
        ]
        XCTAssertEqual(ChatBubbleLogic.grouped(lines).count, 3)
    }

    func testGroupedEmptyInputProducesNoGroups() {
        XCTAssertTrue(ChatBubbleLogic.grouped([]).isEmpty)
    }

    // MARK: - ChatBubbleLogic: inserción de marcadores de pausa en la línea de tiempo

    private func pause(offset: TimeInterval, startEpoch: TimeInterval = 0, endEpoch: TimeInterval = 60) -> PauseInterval {
        PauseInterval(
            start: Date(timeIntervalSince1970: startEpoch),
            end: Date(timeIntervalSince1970: endEpoch),
            transcriptOffsetSeconds: offset
        )
    }

    func testTimelinePlacesPauseBetweenGroups() {
        let lines = [
            LiveTranscriptLine(speaker: LiveTranscriptFeed.youLabel, text: "antes", timestamp: 0),
            LiveTranscriptLine(speaker: LiveTranscriptFeed.themLabel, text: "despues", timestamp: 20)
        ]
        let timeline = ChatBubbleLogic.timeline(lines: lines, pauses: [pause(offset: 10)])
        XCTAssertEqual(timeline.count, 3)
        guard case .messages(let first) = timeline[0], case .pause = timeline[1], case .messages(let third) = timeline[2] else {
            return XCTFail("orden inesperado: \(timeline)")
        }
        XCTAssertEqual(first.messages.map(\.text), ["antes"])
        XCTAssertEqual(third.messages.map(\.text), ["despues"])
    }

    func testTimelineSplitsSameSpeakerGroupAcrossPause() {
        let lines = [
            LiveTranscriptLine(speaker: LiveTranscriptFeed.youLabel, text: "parte1", timestamp: 0),
            LiveTranscriptLine(speaker: LiveTranscriptFeed.youLabel, text: "parte2", timestamp: 20)
        ]
        let timeline = ChatBubbleLogic.timeline(lines: lines, pauses: [pause(offset: 10)])
        XCTAssertEqual(timeline.count, 3)
        guard case .messages(let first) = timeline[0], case .pause = timeline[1], case .messages(let second) = timeline[2] else {
            return XCTFail("orden inesperado: \(timeline)")
        }
        XCTAssertEqual(first.messages.map(\.text), ["parte1"])
        XCTAssertEqual(second.messages.map(\.text), ["parte2"])
    }

    func testTimelineAppendsTrailingPauseAfterLastMessage() {
        let lines = [LiveTranscriptLine(speaker: LiveTranscriptFeed.youLabel, text: "ultimo", timestamp: 0)]
        let timeline = ChatBubbleLogic.timeline(lines: lines, pauses: [pause(offset: 50)])
        XCTAssertEqual(timeline.count, 2)
        guard case .messages = timeline[0], case .pause = timeline[1] else {
            return XCTFail("orden inesperado: \(timeline)")
        }
    }

    func testTimelineWithNoPausesOnlyGroupsMessages() {
        let lines = [LiveTranscriptLine(speaker: LiveTranscriptFeed.youLabel, text: "solo", timestamp: 0)]
        let timeline = ChatBubbleLogic.timeline(lines: lines, pauses: [])
        XCTAssertEqual(timeline.count, 1)
        guard case .messages = timeline[0] else { return XCTFail("se esperaba un grupo de mensajes") }
    }

    func testTimelineOrdersMultiplePausesByOffset() {
        let lines = [
            LiveTranscriptLine(speaker: LiveTranscriptFeed.youLabel, text: "uno", timestamp: 0),
            LiveTranscriptLine(speaker: LiveTranscriptFeed.youLabel, text: "dos", timestamp: 50)
        ]
        let timeline = ChatBubbleLogic.timeline(lines: lines, pauses: [pause(offset: 40), pause(offset: 10)])
        XCTAssertEqual(timeline.map(\.offset), [0, 10, 40, 50])
    }

    // MARK: - ChatPanelLayout: decisión de anclaje según bordes de pantalla

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testAnchorPrefersTrailingWhenSpaceOnBothSides() {
        let pill = CGRect(x: 600, y: 700, width: 232, height: 180)
        XCTAssertEqual(ChatPanelLayout.anchor(pillFrame: pill, screenFrame: screen, panelWidth: 320), .trailing)
    }

    func testAnchorSwitchesToLeadingWhenPillNearRightEdge() {
        let pill = CGRect(x: 1300, y: 700, width: 232, height: 180)
        XCTAssertEqual(ChatPanelLayout.anchor(pillFrame: pill, screenFrame: screen, panelWidth: 320), .leading)
    }

    func testAnchorFallsBackToSideWithMoreSpaceWhenNeitherFits() {
        // Ancho total (400) menos la píldora (232) deja a lo sumo 168pt libres por lado,
        // por debajo del umbral (panelWidth 320 + gap), así que ningún lado "cabe": gana el
        // que tenga más espacio relativo (aquí, la izquierda: 118 contra 50 a la derecha).
        let narrowScreen = CGRect(x: 0, y: 0, width: 400, height: 900)
        let pill = CGRect(x: 118, y: 700, width: 232, height: 180)
        XCTAssertEqual(ChatPanelLayout.anchor(pillFrame: pill, screenFrame: narrowScreen, panelWidth: 320), .leading)
    }

    func testOriginPlacesTrailingPanelRightOfPillAndAlignsTop() {
        let pill = CGRect(x: 600, y: 700, width: 232, height: 180)
        let size = CGSize(width: 320, height: 380)
        let origin = ChatPanelLayout.origin(pillFrame: pill, screenFrame: screen, panelSize: size, anchor: .trailing)
        XCTAssertEqual(origin.x, pill.maxX + ChatPanelLayout.gap, accuracy: 0.001)
        XCTAssertEqual(origin.y, pill.maxY - size.height, accuracy: 0.001)
    }

    func testOriginPlacesLeadingPanelLeftOfPill() {
        let pill = CGRect(x: 1300, y: 700, width: 232, height: 180)
        let size = CGSize(width: 320, height: 380)
        let origin = ChatPanelLayout.origin(pillFrame: pill, screenFrame: screen, panelSize: size, anchor: .leading)
        XCTAssertEqual(origin.x, pill.minX - size.width - ChatPanelLayout.gap, accuracy: 0.001)
    }

    func testOriginClampsVerticallyWithinScreen() {
        let pill = CGRect(x: 600, y: 850, width: 232, height: 180)
        let size = CGSize(width: 320, height: 380)
        let origin = ChatPanelLayout.origin(pillFrame: pill, screenFrame: screen, panelSize: size, anchor: .trailing)
        XCTAssertEqual(origin.y, screen.maxY - size.height, accuracy: 0.001)
    }

    func testOriginClampsHorizontallyWithinScreen() {
        let pill = CGRect(x: -50, y: 700, width: 232, height: 180)
        let size = CGSize(width: 320, height: 380)
        let origin = ChatPanelLayout.origin(pillFrame: pill, screenFrame: screen, panelSize: size, anchor: .leading)
        XCTAssertEqual(origin.x, screen.minX, accuracy: 0.001)
    }
}
