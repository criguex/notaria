import XCTest
@testable import aria_capture

final class GenericImporterTests: XCTestCase {

    private var tempDir: URL!
    private var importDir: URL!
    private var notesDir: URL!
    private var store: MeetingStore!
    private var writer: ObsidianWriter!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-import-tests-\(UUID().uuidString)", isDirectory: true)
        importDir = tempDir.appendingPathComponent("import", isDirectory: true)
        notesDir = tempDir.appendingPathComponent("Reuniones", isDirectory: true)
        try FileManager.default.createDirectory(at: importDir, withIntermediateDirectories: true)
        store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        writer = ObsidianWriter(directory: notesDir)
    }

    override func tearDownWithError() throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    @discardableResult
    private func write(_ name: String, _ content: String, in directory: URL? = nil) throws -> URL {
        let dir: URL = directory ?? importDir
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func importAll(sourceOverride: String? = nil) throws -> ImportResult {
        try GenericImporter.importPath(importDir, sourceOverride: sourceOverride, writer: writer, store: store)
    }

    // MARK: - Markdown con frontmatter

    func testImportMarkdownWithFrontmatterUsesMetadataAndIsFindable() throws {
        try write("sesion-ficticia.md", """
        ---
        title: Sesión ficticia de prueba
        date: 2026-03-10T09:00:00-05:00
        attendees: [Persona Ficticia Uno, Persona Ficticia Dos]
        source: notas-propias
        id: sesion-001
        ---

        ## Resumen inventado

        Punto de prueba sobre un tema ficticio cualquiera.
        """)

        let result = try importAll()
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.updated, 0)
        XCTAssertTrue(result.failed.isEmpty)

        let records = try store.recentMeetings()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].source, "notas-propias")
        XCTAssertEqual(records[0].externalID, "notas-propias:sesion-001")
        XCTAssertEqual(records[0].title, "Sesión ficticia de prueba")

        let content = try String(contentsOfFile: records[0].notePath, encoding: .utf8)
        XCTAssertTrue(content.contains("fuente: notas-propias"))
        XCTAssertTrue(content.contains("Punto de prueba sobre un tema ficticio"))

        let hits = try MeetingSearch.search("tema ficticio", store: store)
        XCTAssertEqual(hits.count, 1)
    }

    // MARK: - Markdown/texto sin frontmatter

    func testImportPlainTextWithoutFrontmatterDerivesTitleFromFilename() throws {
        try write("notas_reunion_de_prueba.txt", "Contenido crudo de una nota ficticia sin metadata.")

        let result = try importAll()
        XCTAssertEqual(result.imported, 1)

        let records = try store.recentMeetings()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].title, "notas reunion de prueba")
        XCTAssertEqual(records[0].source, "notes")

        let content = try String(contentsOfFile: records[0].notePath, encoding: .utf8)
        XCTAssertTrue(content.contains("Contenido crudo de una nota ficticia"))
    }

    // MARK: - VTT con etiquetas <v>

    func testImportVTTWithSpeakerTagsProducesTimedSegments() throws {
        try write("llamada-ficticia.vtt", """
        WEBVTT

        00:00:00.000 --> 00:00:02.500
        <v Hablante Ficticio Uno>Hola a todos, empecemos la sesión inventada.

        00:00:02.500 --> 00:00:05.000
        <v Hablante Ficticio Dos>Perfecto, comparto pantalla con el tema de prueba.
        """)

        let result = try importAll()
        XCTAssertEqual(result.imported, 1)

        let records = try store.recentMeetings()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].source, "vtt")

        let segments = try store.segments(meetingID: records[0].id)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].speaker, "Hablante Ficticio Uno")
        XCTAssertEqual(segments[0].start, 0)
        XCTAssertEqual(segments[1].start, 2.5, accuracy: 0.001)
        XCTAssertTrue(segments[1].text.contains("tema de prueba"))

        let content = try String(contentsOfFile: records[0].notePath, encoding: .utf8)
        XCTAssertTrue(content.contains("Transcript"))
    }

    // MARK: - SRT con prefijo "Nombre:"

    func testImportSRTWithNamePrefixExtractsSpeakers() throws {
        try write("transcript-ficticio.srt", """
        1
        00:00:00,000 --> 00:00:03,000
        Persona Ficticia A: Buenas, iniciamos con el tema inventado.

        2
        00:00:03,000 --> 00:00:06,000
        Persona Ficticia B: De acuerdo, sigo yo con el punto de prueba.
        """)

        let result = try importAll()
        XCTAssertEqual(result.imported, 1)

        let records = try store.recentMeetings()
        let segments = try store.segments(meetingID: records[0].id)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].speaker, "Persona Ficticia A")
        XCTAssertEqual(segments[1].speaker, "Persona Ficticia B")
        XCTAssertEqual(records[0].source, "srt")
    }

    // MARK: - JSON con esquema genérico

    func testImportGenericJSONRecord() throws {
        try write("nota-generica.json", """
        {
          "source": "app-ficticia",
          "id": "registro-001",
          "title": "Reunión ficticia vía JSON",
          "date": "2026-04-01T08:00:00-05:00",
          "attendees": ["Persona Ficticia Uno"],
          "body": "## Resumen inventado\\n\\nTema de prueba en JSON.",
          "transcript": "Persona Ficticia Uno: línea de transcript ficticia",
          "url": "https://ejemplo.inventado/registro-001"
        }
        """)

        let result = try importAll()
        XCTAssertEqual(result.imported, 1)

        let records = try store.recentMeetings()
        XCTAssertEqual(records[0].source, "app-ficticia")
        XCTAssertEqual(records[0].externalID, "app-ficticia:registro-001")

        let content = try String(contentsOfFile: records[0].notePath, encoding: .utf8)
        XCTAssertTrue(content.contains("Tema de prueba en JSON"))
        XCTAssertTrue(content.contains("Ver original"))
        XCTAssertFalse(content.contains("Granola"), "el importador genérico no debe nombrar productos de terceros")
    }

    // MARK: - JSON con los alias del exportador de Granola

    func testImportJSONAcceptsGranolaExporterShape() throws {
        try write("granola-ficticia.json", """
        {
          "source": "granola",
          "id": "aaaaaaaa-0000-0000-0000-00000000ffff",
          "title": "Reunión ficticia estilo Granola",
          "meeting_at": "2026-05-01T10:00:00-05:00",
          "url": "https://notes.ejemplo-ficticio.ai/d/aaaaaaaa-0000-0000-0000-00000000ffff",
          "participants": ["Persona Ficticia Tres"],
          "summary_markdown": "Resumen con nombre de campo estilo exportador",
          "transcript": null,
          "transcript_unavailable": true
        }
        """)

        let result = try importAll()
        XCTAssertEqual(result.imported, 1)

        let records = try store.recentMeetings()
        XCTAssertEqual(records[0].source, "granola")
        XCTAssertEqual(records[0].externalID, "granola:aaaaaaaa-0000-0000-0000-00000000ffff")

        let content = try String(contentsOfFile: records[0].notePath, encoding: .utf8)
        XCTAssertTrue(content.contains("Resumen con nombre de campo estilo exportador"))
    }

    // MARK: - Arreglo JSON con varios registros

    func testImportJSONArrayProducesOneNotePerElement() throws {
        try write("lote-ficticio.json", """
        [
          { "title": "Primer registro ficticio", "body": "Cuerpo uno." },
          { "title": "Segundo registro ficticio", "body": "Cuerpo dos." }
        ]
        """)

        let result = try importAll(sourceOverride: "lote")
        XCTAssertEqual(result.imported, 2)

        let records = try store.recentMeetings()
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.source == "lote" })
    }

    // MARK: - --source pisa la fuente de cada ítem

    func testSourceFlagOverridesPerFileSource() throws {
        try write("sesion.md", """
        ---
        title: Sesión con fuente propia
        source: original
        id: sesion-override
        ---
        Cuerpo ficticio.
        """)

        let result = try importAll(sourceOverride: "forzado")
        XCTAssertEqual(result.imported, 1)
        let records = try store.recentMeetings()
        XCTAssertEqual(records[0].source, "forzado")
        XCTAssertEqual(records[0].externalID, "forzado:sesion-override")
    }

    // MARK: - Idempotencia / duplicados

    func testReimportSameMarkdownIsIdempotent() throws {
        try write("repetible.md", """
        ---
        title: Nota repetible ficticia
        id: repetible-001
        ---
        Versión original del contenido ficticio.
        """)

        let first = try importAll()
        XCTAssertEqual(first.imported, 1)
        let firstRecords = try store.recentMeetings()
        let notePath = firstRecords[0].notePath

        let second = try importAll()
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.updated, 1)

        let secondRecords = try store.recentMeetings()
        XCTAssertEqual(secondRecords.count, 1, "no debe duplicar la nota al re-importar sin cambios")
        XCTAssertEqual(secondRecords[0].notePath, notePath)

        let allFiles = try FileManager.default.contentsOfDirectory(atPath: notesDir.path)
        XCTAssertEqual(allFiles.count, 1, "no debe quedar un segundo .md por colisión de nombre")
    }

    func testReimportChangedMarkdownWithoutIDUpdatesSameNoteWhenHashMatchesButDiffersWhenContentChanges() throws {
        try write("sin-id.md", "Contenido ficticio versión uno sin frontmatter.")
        let first = try importAll()
        XCTAssertEqual(first.imported, 1)

        let secondSameContent = try importAll()
        XCTAssertEqual(secondSameContent.imported, 0)
        XCTAssertEqual(secondSameContent.updated, 1, "mismo contenido → mismo hash → debe actualizar, no duplicar")

        try write("sin-id.md", "Contenido ficticio versión dos, con un cambio real.")
        let third = try importAll()
        XCTAssertEqual(third.imported, 1, "contenido distinto sin id estable → nuevo hash → nueva nota")

        let records = try store.recentMeetings()
        XCTAssertEqual(records.count, 2)
    }

    // MARK: - Fallidos no detienen el resto del lote

    func testInvalidJSONGoesToFailedWithoutStoppingOtherImports() throws {
        try write("invalido.json", "{ not valid json ")
        try write("valido.md", """
        ---
        title: Nota válida junto a una inválida
        id: valida-001
        ---
        Contenido ficticio válido.
        """)

        let result = try importAll()
        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.failed.count, 1)
        XCTAssertEqual(result.failed.first?.file, "invalido.json")
    }

    // MARK: - Importar un solo archivo (no carpeta)

    func testImportSingleFilePathDirectly() throws {
        let fileURL = try write("archivo-suelto.md", """
        ---
        title: Nota de archivo suelto
        id: suelto-001
        ---
        Contenido ficticio de un archivo importado directamente.
        """)

        let result = try GenericImporter.importPath(fileURL, sourceOverride: nil, writer: writer, store: store)
        XCTAssertEqual(result.imported, 1)
        let records = try store.recentMeetings()
        XCTAssertEqual(records[0].externalID, "notes:suelto-001")
    }

    // MARK: - Ruta inexistente

    func testImportMissingPathThrows() throws {
        let missing = tempDir.appendingPathComponent("no-existe", isDirectory: true)
        XCTAssertThrowsError(try GenericImporter.importPath(missing, sourceOverride: nil, writer: writer, store: store))
    }
}
