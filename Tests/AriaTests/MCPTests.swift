import XCTest
@testable import aria_capture

final class MCPTests: XCTestCase {

    private var tempDir: URL!
    private var server: MCPServer!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        try store.saveMeeting(
            date: Date(timeIntervalSince1970: 1_754_000_000),
            title: "Sync piloto",
            durationSeconds: 900,
            notePath: "/tmp/n.md",
            wavPath: nil,
            segments: [TranscriptSegment(start: 0, end: 5, text: "Falta la regresión.", speaker: "Otros")],
            quickNotes: [QuickNote(timestamp: "10:00", text: "pedir accesos")]
        )
        server = try MCPServer(store: store)
    }

    override func tearDownWithError() throws {
        server = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func result(of line: String) throws -> [String: Any] {
        let response = try XCTUnwrap(server.handle(line))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        return object
    }

    private func contentText(_ object: [String: Any]) -> String? {
        (((object["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"]) as? String
    }

    func testInitializeAndToolsList() throws {
        let initialized = try result(of: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        let initResult = try XCTUnwrap(initialized["result"] as? [String: Any])
        XCTAssertEqual(initResult["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual((initResult["serverInfo"] as? [String: Any])?["name"] as? String, "aria")

        let tools = try result(of: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let list = try XCTUnwrap((tools["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(list.map { $0["name"] as? String }, ["search_meetings", "list_meetings", "get_meeting"])
    }

    func testToolCallsOverSeededStore() throws {
        let search = try result(of: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_meetings","arguments":{"query":"regresion"}}}"#)
        XCTAssertTrue(try XCTUnwrap(contentText(search)).contains("Sync piloto"))

        let list = try result(of: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_meetings","arguments":{}}}"#)
        XCTAssertTrue(try XCTUnwrap(contentText(list)).contains("[1]"))

        let meeting = try result(of: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_meeting","arguments":{"id":1}}}"#)
        let text = try XCTUnwrap(contentText(meeting))
        XCTAssertTrue(text.contains("# Sync piloto"))
        XCTAssertTrue(text.contains("Falta la regresión."))
        XCTAssertTrue(text.contains("pedir accesos"))

        let missing = try result(of: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"get_meeting","arguments":{"id":99}}}"#)
        XCTAssertEqual((missing["result"] as? [String: Any])?["isError"] as? Bool, true)
    }

    func testNotificationsAndUnknownMethods() throws {
        XCTAssertNil(server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        XCTAssertNil(server.handle("no es json"))
        let unknown = try result(of: #"{"jsonrpc":"2.0","id":7,"method":"resources/list"}"#)
        XCTAssertEqual(((unknown["error"] as? [String: Any])?["code"] as? Int), -32601)
    }
}

extension MCPTests {

    func testGetMeetingAcceptsNumericStringID() throws {
        let meeting = try result(of: #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"get_meeting","arguments":{"id":"1"}}}"#)
        XCTAssertTrue(try XCTUnwrap(contentText(meeting)).contains("# Sync piloto"))
        XCTAssertEqual(MCPServer.intValue("7"), 7)
        XCTAssertEqual(MCPServer.intValue(7), 7)
        XCTAssertNil(MCPServer.intValue("siete"))
        XCTAssertNil(MCPServer.intValue(nil))
    }
}
