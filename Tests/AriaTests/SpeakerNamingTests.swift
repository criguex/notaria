import XCTest
@testable import aria_capture

final class SpeakerNamingTests: XCTestCase {

    // MARK: - orderedSpeakerLabels / speakingSeconds

    func testOrderedSpeakerLabelsExcludesMicAndDedupesInOrder() {
        let segments = [
            TranscriptSegment(start: 0, end: 1, text: "a", speaker: "Yo"),
            TranscriptSegment(start: 1, end: 2, text: "b", speaker: "Hablante 2"),
            TranscriptSegment(start: 2, end: 3, text: "c", speaker: "Hablante 1"),
            TranscriptSegment(start: 3, end: 4, text: "d", speaker: "Hablante 2")
        ]
        XCTAssertEqual(SpeakerNaming.orderedSpeakerLabels(in: segments), ["Hablante 2", "Hablante 1"])
    }

    func testSpeakingSecondsSumsPerSpeaker() {
        let segments = [
            TranscriptSegment(start: 0, end: 3, text: "a", speaker: "Yo"),
            TranscriptSegment(start: 3, end: 5, text: "b", speaker: "Hablante 1"),
            TranscriptSegment(start: 5, end: 6.5, text: "c", speaker: "Hablante 1")
        ]
        let totals = SpeakerNaming.speakingSeconds(in: segments)
        XCTAssertEqual(totals["Yo"], 3)
        XCTAssertEqual(totals["Hablante 1"]!, 3.5, accuracy: 0.001)
    }

    // MARK: - extractMentionedNames

    func testExtractsVocativeNameAfterLeadIn() {
        XCTAssertEqual(SpeakerNaming.extractMentionedNames(from: "Gracias, Ana por el reporte"), ["Ana"])
        XCTAssertEqual(SpeakerNaming.extractMentionedNames(from: "oye Juan ¿tienes el dato?"), ["Juan"])
    }

    func testExtractsNameAtSentenceStartBeforeComma() {
        XCTAssertEqual(SpeakerNaming.extractMentionedNames(from: "Ana, ¿qué opinas tú?"), ["Ana"])
    }

    func testIgnoresCommonSentenceStartersAndLowercaseWords() {
        XCTAssertEqual(SpeakerNaming.extractMentionedNames(from: "Bueno, empecemos la reunión."), [])
        XCTAssertEqual(SpeakerNaming.extractMentionedNames(from: "entonces vamos con el resumen"), [])
    }

    func testExtractMentionedNamesHandlesEmptyText() {
        XCTAssertEqual(SpeakerNaming.extractMentionedNames(from: ""), [])
    }

    // MARK: - attributedMentions

    func testAttributedMentionsAssignsToAdjacentDifferentSpeaker() {
        let segments = [
            TranscriptSegment(start: 0, end: 2, text: "¿y el presupuesto?", speaker: "Hablante 1"),
            TranscriptSegment(start: 2, end: 4, text: "lo tengo listo", speaker: "Hablante 2"),
            TranscriptSegment(start: 4, end: 6, text: "gracias, Ana", speaker: "Hablante 1")
        ]
        let mentions = SpeakerNaming.attributedMentions(in: segments)
        XCTAssertEqual(mentions["Hablante 2"], ["Ana"])
    }

    // MARK: - resolve / confidence tiers

    func testResolveVoiceMemoryOverridesEverythingElse() {
        let segments = [TranscriptSegment(start: 0, end: 1, text: "hola", speaker: "Hablante 1")]
        let assignments = SpeakerNaming.resolve(
            speakerLabels: ["Hablante 1"],
            segments: segments,
            calendarAttendees: ["Juan"],
            voiceMemoryMatches: ["Hablante 1": (name: "Ana", confidence: 0.9)]
        )
        XCTAssertEqual(assignments["Hablante 1"]?.name, "Ana")
        XCTAssertEqual(assignments["Hablante 1"]?.source, .voiceMemory)
        XCTAssertGreaterThanOrEqual(assignments["Hablante 1"]!.confidence, SpeakerAssignment.highConfidence)
    }

    func testResolveMentionedNameMatchingAttendeeIsHighConfidence() {
        let segments = [
            TranscriptSegment(start: 0, end: 2, text: "¿todo bien?", speaker: "Hablante 2"),
            TranscriptSegment(start: 2, end: 4, text: "sí, gracias Ana", speaker: "Hablante 1")
        ]
        let assignments = SpeakerNaming.resolve(
            speakerLabels: ["Hablante 1", "Hablante 2"],
            segments: segments,
            calendarAttendees: ["Ana García"]
        )
        XCTAssertEqual(assignments["Hablante 2"]?.name, "Ana")
        XCTAssertGreaterThanOrEqual(assignments["Hablante 2"]!.confidence, SpeakerAssignment.highConfidence)
        XCTAssertEqual(assignments["Hablante 2"]?.source, .mentionedAndAttendee)
    }

    func testResolveMentionedNameWithoutAttendeeMatchIsLowConfidence() throws {
        let segments = [
            TranscriptSegment(start: 0, end: 2, text: "¿todo bien?", speaker: "Hablante 2"),
            TranscriptSegment(start: 2, end: 4, text: "sí, gracias Pedro", speaker: "Hablante 1")
        ]
        let assignments = SpeakerNaming.resolve(
            speakerLabels: ["Hablante 1", "Hablante 2"],
            segments: segments,
            calendarAttendees: []
        )
        let assignment = try XCTUnwrap(assignments["Hablante 2"])
        XCTAssertLessThan(assignment.confidence, SpeakerAssignment.highConfidence)
        XCTAssertGreaterThanOrEqual(assignment.confidence, SpeakerAssignment.minConfidence)
        XCTAssertEqual(assignment.source, .mentioned)
    }

    func testResolveFallsBackToCalendarOrderWhenCountsMatch() {
        let segments = [
            TranscriptSegment(start: 0, end: 1, text: "hola", speaker: "Hablante 1"),
            TranscriptSegment(start: 1, end: 2, text: "hola", speaker: "Hablante 2")
        ]
        let assignments = SpeakerNaming.resolve(
            speakerLabels: ["Hablante 1", "Hablante 2"],
            segments: segments,
            calendarAttendees: ["Ana", "Luis"]
        )
        XCTAssertEqual(assignments["Hablante 1"]?.name, "Ana")
        XCTAssertEqual(assignments["Hablante 1"]?.source, .calendarOrder)
        XCTAssertLessThan(assignments["Hablante 1"]!.confidence, SpeakerAssignment.highConfidence)
    }

    func testResolveReturnsNoSuggestionWithoutAnySignal() {
        let segments = [TranscriptSegment(start: 0, end: 1, text: "hola", speaker: "Hablante 1")]
        let assignments = SpeakerNaming.resolve(speakerLabels: ["Hablante 1"], segments: segments, calendarAttendees: [])
        XCTAssertNil(assignments["Hablante 1"])
    }

    // MARK: - displayLabel / applyAssignments

    func testDisplayLabelHighConfidenceUsesPlainName() {
        let assignment = SpeakerAssignment(name: "Ana", confidence: 0.9, source: .voiceMemory)
        XCTAssertEqual(assignment.displayLabel(for: "Hablante 1"), "Ana")
    }

    func testDisplayLabelLowConfidenceUsesPendingFormat() {
        let assignment = SpeakerAssignment(name: "Ana", confidence: 0.4, source: .mentioned)
        XCTAssertEqual(assignment.displayLabel(for: "Hablante 1"), "Hablante 1 (¿Ana?)")
    }

    func testDisplayLabelBelowMinConfidenceKeepsOriginal() {
        let assignment = SpeakerAssignment(name: "Ana", confidence: 0.1, source: .mentioned)
        XCTAssertEqual(assignment.displayLabel(for: "Hablante 1"), "Hablante 1")
    }

    func testApplyAssignmentsRenamesMatchingSegmentsOnly() {
        let segments = [
            TranscriptSegment(start: 0, end: 1, text: "a", speaker: "Yo"),
            TranscriptSegment(start: 1, end: 2, text: "b", speaker: "Hablante 1")
        ]
        let assignments = ["Hablante 1": SpeakerAssignment(name: "Ana", confidence: 0.9, source: .voiceMemory)]
        let updated = SpeakerNaming.applyAssignments(to: segments, assignments: assignments)
        XCTAssertEqual(updated[0].speaker, "Yo")
        XCTAssertEqual(updated[1].speaker, "Ana")
    }

    // MARK: - pendingConfirmation / cleanLabel

    func testPendingConfirmationParsesLabel() throws {
        let parsed = try XCTUnwrap(SpeakerNaming.pendingConfirmation(in: "Hablante 2 (¿Ana María?)"))
        XCTAssertEqual(parsed.base, "Hablante 2")
        XCTAssertEqual(parsed.suggestedName, "Ana María")
    }

    func testPendingConfirmationNilForPlainLabel() {
        XCTAssertNil(SpeakerNaming.pendingConfirmation(in: "Hablante 2"))
        XCTAssertNil(SpeakerNaming.pendingConfirmation(in: "Ana"))
    }

    func testCleanLabelStripsPendingSuffix() {
        XCTAssertEqual(SpeakerNaming.cleanLabel("Hablante 2 (¿Ana?)"), "Hablante 2")
        XCTAssertEqual(SpeakerNaming.cleanLabel("Ana"), "Ana")
    }

    // MARK: - AriaConfig opt-ins

    func testSpeakerConfigDefaultsAreOff() {
        let config = AriaConfig()
        XCTAssertFalse(config.speakerSeparationEnabled)
        XCTAssertFalse(config.voiceMemoryEnabled)
        XCTAssertFalse(config.participantsAccessibilityEnabled)
    }

    func testSpeakerConfigSetAndValidate() throws {
        var config = AriaConfig()
        try config.set(key: "speakerSeparationEnabled", value: "true")
        try config.set(key: "voiceMemoryEnabled", value: "true")
        try config.set(key: "participantsAccessibilityEnabled", value: "true")
        XCTAssertTrue(config.speakerSeparationEnabled)
        XCTAssertTrue(config.voiceMemoryEnabled)
        XCTAssertTrue(config.participantsAccessibilityEnabled)

        XCTAssertThrowsError(try config.set(key: "speakerSeparationEnabled", value: "quizás"))
        XCTAssertTrue(AriaConfig().listing.contains("speakerSeparationEnabled"))
    }

    /// Transcript real (reunión sintética de QA E2E, 3 participantes: "Yo" + dos voces separadas
    /// en el canal del sistema). "Yo" modera entre dos hablantes DISTINTOS repetidamente — antes
    /// del fix, cualquier primera palabra de un turno ("Buenas", "Dale", "Perdón"...) se contaba
    /// como nombre y las menciones de "Yo" se mezclaban entre los dos vecinos sin importar a
    /// quién se dirigían, así que ambos hablantes terminaban sugeridos con el MISMO nombre.
    func testResolveRealMeetingTranscriptAssignsEachSpeakerItsOwnName() {
        let raw: [(String, String)] = [
            ("Yo", "Buenas, empecemos el SIG de QA del Sprint. Ana, Juan, ¿cómo vamos con las pruebas de regresión?"),
            ("Hablante 1", "Hola Ana, terminé la regresión del módulo de pagos, todo verde menos un caso."),
            ("Hablante 2", "Por mi lado dejé vista la suite de autenticación, pero encontré un Google NLogin con Google."),
            ("Yo", "Vale, cuéntame ese back de login, Juan."),
            ("Hablante 2", "Cuando el usuario cancela el popup de gole, la aplicación se queda cargando para siempre. Ya abrí el ticket QA482. Chau, chau, chau."),
            ("Yo", "Perfecto, gracias Juan. Lo marcamos como bloqueante para el release del viernes. Ana, ¿cuál es el caso que falló en pagos?"),
            ("Hablante 1", "El reembolso parcial no actualiza el saldo si la moneda es distinta a pesos. Voy a reproducirlo hoy mismo. no."),
            ("Yo", "Dale. Entonces, Decisión, fue la regla del back de Google Login, Anna reproduce y documenta el back de reembolso, y yo reviso el reporte con el equipo de producto."),
            ("Hablante 1", "Me parece bien. También propongo que subamos la cobertura de automatización en el check out, está quedando corto."),
            ("Yo", "Buena idea, la metemos al backlog del próximo sprint. Ana, ¿puedes crear el ticket?"),
            ("Hablante 1", "Sí, lo creo esta tarde."),
            ("Yo", "Genial, gracias Ana, algo más antes de cerrar?"),
            ("Hablante 2", "Perdón, se cayó el internet un momento. Solo quería confirmar que el deploy está y queda para hoy en la tarde."),
            ("Yo", "Sí, confirmado. Entonces resumen, Juan corrige el bug cua 482 y hace el deploy a staging hoy, Ana documenta el bug de reembolso y crea el ticket de cobertura de checkout. Yo hablo con producto sobre el reporte de regresión. Nos vemos el jueves. Gracias. Ana. Gracias, Juan."),
            ("Hablante 1", "Gracias a ti, Christian. Nos vemos."),
            ("Hablante 2", "Chao, buen resto de día.")
        ]
        let segments = raw.enumerated().map { i, pair in
            TranscriptSegment(start: Double(i), end: Double(i) + 1, text: pair.1, speaker: pair.0)
        }
        let assignments = SpeakerNaming.resolve(
            speakerLabels: ["Hablante 1", "Hablante 2"],
            segments: segments,
            calendarAttendees: []
        )
        XCTAssertEqual(assignments["Hablante 1"]?.name, "Ana")
        XCTAssertEqual(assignments["Hablante 2"]?.name, "Juan")
        XCTAssertNotEqual(assignments["Hablante 1"]?.name, assignments["Hablante 2"]?.name)
    }
}
