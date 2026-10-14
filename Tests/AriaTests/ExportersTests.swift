import XCTest
@testable import aria_capture

final class ExportersTests: XCTestCase {

    func testClipboardExporterMarkdown() throws {
        let markdown = "# Reunion\n\n## Resumen\n\n- Punto 1\n- Punto 2"
        let exporter = ClipboardExporter(title: "Reunion", noteMarkdown: markdown)
        try exporter.copyAsMarkdown()

        let pasteboard = NSPasteboard.general
        let content = pasteboard.string(forType: .string)
        XCTAssertEqual(content, markdown)
    }

    func testClipboardExporterRich() throws {
        let markdown = "# Titulo\n\nParrafo con contenido"
        let exporter = ClipboardExporter(title: "Titulo", noteMarkdown: markdown)
        try exporter.copyAsRich()

        let pasteboard = NSPasteboard.general
        let content = pasteboard.string(forType: .string)
        XCTAssertNotNil(content)
        XCTAssertEqual(content, markdown)
    }

    func testPDFExporterCreatesFile() throws {
        let markdown = "# Titulo de prueba\n\nContenido del PDF"
        let exporter = PDFExporter(title: "PDF Test", noteMarkdown: markdown, date: Date())

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.pdf")
        try exporter.exportToFile(at: tempURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        let data = try Data(contentsOf: tempURL)
        XCTAssertGreaterThan(data.count, 0)

        try? FileManager.default.removeItem(at: tempURL)
    }

    func testSlackExporterInitialization() throws {
        let exporter = SlackExporter(
            title: "Test",
            noteMarkdown: "# Contenido",
            date: Date(),
            webhookURL: URL(string: "https://hooks.slack.com/services/mock")!
        )
        XCTAssertEqual(exporter.title, "Test")
        XCTAssertTrue(exporter.noteMarkdown.contains("Contenido"))
    }

    func testNotionExporterInitialization() throws {
        let exporter = NotionExporter(
            title: "Test",
            noteMarkdown: "# Titulo\n\nContenido",
            date: Date(),
            token: "test-token",
            parentDatabaseID: "test-db-id"
        )
        XCTAssertEqual(exporter.title, "Test")
        XCTAssertEqual(exporter.token, "test-token")
        XCTAssertEqual(exporter.parentDatabaseID, "test-db-id")
    }

    func testPDFExporterWithComplexMarkdown() throws {
        let markdown = """
        # Titulo Principal

        ## Seccion 1

        Contenido del parrafo con varias lineas.

        - Item 1
        - Item 2
        - Item 3

        ## Seccion 2

        > Nota importante

        Fin del contenido.
        """
        let exporter = PDFExporter(title: "Complex PDF", noteMarkdown: markdown, date: Date())

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("complex.pdf")
        try exporter.exportToFile(at: tempURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        let data = try Data(contentsOf: tempURL)
        XCTAssertGreaterThan(data.count, 100)

        try? FileManager.default.removeItem(at: tempURL)
    }
}
