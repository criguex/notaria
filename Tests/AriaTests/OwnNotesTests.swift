import XCTest
@testable import aria_capture

final class OwnNotesTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-ownnotes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Nombre y ruta del borrador

    func testDraftFileNameIsDeterministicFromDate() {
        let since = Date(timeIntervalSince1970: 1_760_000_000)
        let name = MeetingNotepadLogic.draftFileName(for: since)
        XCTAssertTrue(name.hasSuffix(" notas.md"))
        XCTAssertEqual(name, MeetingNotepadLogic.draftFileName(for: since))

        let url = MeetingNotepadLogic.draftURL(for: since, in: tempDir)
        XCTAssertEqual(url.deletingLastPathComponent(), tempDir)
        XCTAssertEqual(url.lastPathComponent, name)
    }

    // MARK: - Persistencia en disco (autosave)

    func testNotepadFileStoreSaveLoadClearRoundtrip() throws {
        let url = tempDir.appendingPathComponent("borrador.md")
        let store = NotepadFileStore(fileURL: url)

        XCTAssertEqual(store.load(), "")
        try store.save("primera línea\nsegunda línea")
        XCTAssertEqual(store.load(), "primera línea\nsegunda línea")

        // Simula una nueva instancia leyendo lo que otra ya guardó (recuperación tras cierre/crash).
        let reopened = NotepadFileStore(fileURL: url)
        XCTAssertEqual(reopened.load(), "primera línea\nsegunda línea")

        try store.clear()
        XCTAssertEqual(store.load(), "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try store.clear()
    }

    func testMergedOwnNotesJoinsNonEmptyPiecesAndTrims() {
        XCTAssertEqual(MeetingNotepadLogic.mergedOwnNotes("  ", ""), "")
        XCTAssertEqual(MeetingNotepadLogic.mergedOwnNotes("  hola  ", ""), "hola")
        XCTAssertEqual(
            MeetingNotepadLogic.mergedOwnNotes(" nota rápida ", " borrador largo \n con detalle "),
            "nota rápida\n\nborrador largo \n con detalle"
        )
    }

    // MARK: - Sección garantizada en la nota final

    func testAppendingOwnNotesSectionAddsSectionWhenNotesPresent() {
        let markdown = "# Sync\n\n## Resumen\nTexto generado."
        let result = MeetingNotepadLogic.appendingOwnNotesSection(to: markdown, ownNotes: "  recordar pedir el presupuesto  ")
        XCTAssertTrue(result.hasSuffix("## Notas propias\nrecordar pedir el presupuesto"))
        XCTAssertTrue(result.hasPrefix(markdown))
    }

    func testAppendingOwnNotesSectionNoOpWhenNotesEmpty() {
        let markdown = "# Sync\n\n## Resumen\nTexto generado."
        XCTAssertEqual(MeetingNotepadLogic.appendingOwnNotesSection(to: markdown, ownNotes: "   "), markdown)
    }

    func testAppendingOwnNotesSectionDoesNotDuplicateIfAlreadyPresent() {
        let markdown = "# Sync\n\n## Notas propias\nya estaba aquí."
        let result = MeetingNotepadLogic.appendingOwnNotesSection(to: markdown, ownNotes: "otra nota distinta")
        XCTAssertEqual(result, markdown)
    }

    // MARK: - Armado del prompt: notas del usuario = estructura, transcript = detalle

    func testComposeUserMessagePlacesOwnNotesBeforeTranscriptAsStructure() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let message = MeetingEnhancer.composeUserMessage(
            transcript: "[00:00] Yo: hola a todos",
            notes: "1. cerrar presupuesto\n2. fecha de entrega",
            date: date,
            durationSeconds: 120
        )
        XCTAssertTrue(message.contains("## Notas del usuario (estructura a respetar)"))
        XCTAssertTrue(message.contains("## Transcript diarizado"))
        let notesRange = message.range(of: "## Notas del usuario")!
        let transcriptRange = message.range(of: "## Transcript diarizado")!
        XCTAssertTrue(notesRange.lowerBound < transcriptRange.lowerBound, "las notas del usuario deben ir antes del transcript")
        XCTAssertTrue(message.contains("cerrar presupuesto"))
    }

    func testComposeUserMessageOmitsNotesHeaderWhenEmpty() {
        let message = MeetingEnhancer.composeUserMessage(
            transcript: "[00:00] Yo: hola",
            notes: "   ",
            date: Date(timeIntervalSince1970: 0),
            durationSeconds: 60
        )
        XCTAssertFalse(message.contains("## Notas del usuario"))
        XCTAssertTrue(message.contains("## Transcript diarizado"))
    }

    // MARK: - MeetingStore: notas propias persistidas y editables

    func testMeetingStoreOwnNotesRoundtripAndUpdate() throws {
        let store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let id = try store.saveMeeting(
            date: Date(), title: "Reunión con notas propias", durationSeconds: 60,
            notePath: "/tmp/nota.md", wavPath: nil, segments: [], quickNotes: [],
            ownNotes: "estructura inicial del usuario"
        )
        XCTAssertEqual(try store.ownNotes(meetingID: id), "estructura inicial del usuario")

        try store.setOwnNotes("estructura editada después de generar la nota", meetingID: id)
        XCTAssertEqual(try store.ownNotes(meetingID: id), "estructura editada después de generar la nota")
    }

    func testMeetingStoreSaveMeetingDefaultsOwnNotesToEmpty() throws {
        let store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let id = try store.saveMeeting(
            date: Date(), title: "Reunión sin notas propias", durationSeconds: 60,
            notePath: "/tmp/nota2.md", wavPath: nil, segments: [], quickNotes: []
        )
        XCTAssertEqual(try store.ownNotes(meetingID: id), "")
    }

    // MARK: - Controlador del editor en vivo (borrador + autosave)

    @MainActor
    func testNotepadControllerBeginLoadsExistingDraftAndFinishClearsFile() throws {
        let since = Date(timeIntervalSince1970: 1_760_000_500)
        let expectedURL = MeetingNotepadLogic.draftURL(for: since, in: tempDir)
        try "nota dejada antes de un cierre inesperado".write(to: expectedURL, atomically: true, encoding: .utf8)

        let controller = MeetingNotepadController(directory: tempDir)
        controller.begin(since: since)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.text, "nota dejada antes de un cierre inesperado")

        controller.text = "nota dejada antes de un cierre inesperado\nsegunda línea añadida"
        controller.persist()
        XCTAssertEqual(try String(contentsOf: expectedURL, encoding: .utf8), controller.text)

        let finalText = controller.finish()
        XCTAssertEqual(finalText, "nota dejada antes de un cierre inesperado\nsegunda línea añadida")
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.text, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedURL.path))
    }

    @MainActor
    func testNotepadControllerResetClearsStateWithoutTouchingDisk() throws {
        let since = Date(timeIntervalSince1970: 1_760_000_900)
        let controller = MeetingNotepadController(directory: tempDir)
        controller.begin(since: since)
        controller.text = "borrador a medio escribir"
        controller.persist()

        controller.reset()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.text, "")

        let url = MeetingNotepadLogic.draftURL(for: since, in: tempDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "reset no debe borrar el borrador del disco")
    }
}
