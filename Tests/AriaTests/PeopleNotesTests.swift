import XCTest
@testable import aria_capture

final class PeopleNotesTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-people-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratch.appendingPathComponent("Reuniones", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private var notesDir: URL { scratch.appendingPathComponent("Reuniones", isDirectory: true) }

    func testPersonNameFromWikilink() {
        XCTAssertEqual(PeopleNotes.personName(fromWikilink: "[[Ana López]]"), "Ana López")
        XCTAssertEqual(PeopleNotes.personName(fromWikilink: "  [[Juan]]  "), "Juan")
        XCTAssertNil(PeopleNotes.personName(fromWikilink: "Otros"))
        XCTAssertNil(PeopleNotes.personName(fromWikilink: "[[]]"))
    }

    func testCompanyFromAddress() {
        XCTAssertEqual(PeopleNotes.company(fromAddress: "mailto:juan.perez@acme.com"), "Acme")
        XCTAssertEqual(PeopleNotes.company(fromAddress: "ana@northwind.com.co"), "Northwind")
        XCTAssertNil(PeopleNotes.company(fromAddress: "mailto:cris@gmail.com"))
        XCTAssertNil(PeopleNotes.company(fromAddress: "sin-arroba"))
    }

    func testEnsureStubsCreatesSiblingsOnceWithoutOverwriting() throws {
        let created = try PeopleNotes.ensureStubs(
            people: ["Ana López", "Juan", "ana lópez"],
            companies: ["Acme"],
            notesDirectory: notesDir
        )
        XCTAssertEqual(created.count, 3)
        let personaURL = scratch.appendingPathComponent("Personas/Ana López.md")
        let empresaURL = scratch.appendingPathComponent("Empresas/Acme.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: personaURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: empresaURL.path))
        XCTAssertTrue(try String(contentsOf: personaURL, encoding: .utf8).contains("tipo: persona"))
        XCTAssertTrue(try String(contentsOf: empresaURL, encoding: .utf8).contains("tipo: empresa"))

        try "mis apuntes sobre Ana".write(to: personaURL, atomically: true, encoding: .utf8)
        let again = try PeopleNotes.ensureStubs(people: ["Ana López"], companies: [], notesDirectory: notesDir)
        XCTAssertEqual(again, [])
        XCTAssertEqual(try String(contentsOf: personaURL, encoding: .utf8), "mis apuntes sobre Ana")
    }

    func testWriterRendersEmpresasAndCreatesStubs() throws {
        let writer = ObsidianWriter(directory: notesDir)
        let note = MeetingNote(
            title: "Sync piloto",
            date: Date(),
            participants: ["[[Ana López]]", "Otros"],
            durationSeconds: 600,
            body: "# Sync",
            transcript: nil,
            companies: ["Acme"]
        )
        let url = try writer.write(note)
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("empresas: [\"[[Acme]]\"]"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("Personas/Ana López.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("Empresas/Acme.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: scratch.appendingPathComponent("Personas/Otros.md").path))

        let plain = MeetingNote(
            title: "Sin empresa",
            date: Date(),
            participants: ["Yo"],
            durationSeconds: 60,
            body: "# Nota",
            transcript: nil
        )
        let plainContent = try String(contentsOf: try writer.write(plain), encoding: .utf8)
        XCTAssertFalse(plainContent.contains("empresas:"))
    }
}
