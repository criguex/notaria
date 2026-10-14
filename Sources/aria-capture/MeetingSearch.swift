import Foundation
import SQLite3

struct SearchHit {
    let meetingID: Int64
    let title: String
    let date: Date
    let kind: String
    let speaker: String
    let snippet: String
}

enum MeetingSearch {

    static func ftsQuery(from raw: String) -> String {
        raw.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"*" }
            .joined(separator: " ")
    }

    static func line(for hit: SearchHit) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let who = hit.speaker.isEmpty ? hit.kind : "\(hit.kind) · \(hit.speaker)"
        return "[\(hit.meetingID)] \(formatter.string(from: hit.date)) · \(hit.title) — (\(who)) \(hit.snippet)"
    }

    static func search(_ raw: String, store providedStore: MeetingStore? = nil, limit: Int = 20) throws -> [SearchHit] {
        let match = ftsQuery(from: raw)
        guard !match.isEmpty else {
            throw Self.error("Consulta vacía. Uso: aria-capture search <palabras>")
        }
        let store = try providedStore ?? MeetingStore()
        let meetings = try store.recentMeetings(limit: 10_000)
        guard !meetings.isEmpty else {
            throw Self.error("Sin reuniones en el historial todavía. Graba una primero (aria-capture menubar).")
        }

        var db: OpaquePointer?
        guard sqlite3_open(":memory:", &db) == SQLITE_OK else {
            throw Self.error("No se pudo crear el índice en memoria.")
        }
        defer { sqlite3_close(db) }

        guard sqlite3_exec(db, """
        CREATE VIRTUAL TABLE fts USING fts5(
            content, title UNINDEXED, meeting_id UNINDEXED, kind UNINDEXED,
            speaker UNINDEXED, date UNINDEXED, tokenize='unicode61 remove_diacritics 2'
        );
        """, nil, nil, nil) == SQLITE_OK else {
            throw Self.error("FTS5 no disponible: \(String(cString: sqlite3_errmsg(db)))")
        }

        var insert: OpaquePointer?
        guard sqlite3_prepare_v2(db, """
        INSERT INTO fts (content, title, meeting_id, kind, speaker, date) VALUES (?, ?, ?, ?, ?, ?)
        """, -1, &insert, nil) == SQLITE_OK else {
            throw Self.error("Preparando el índice: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(insert) }

        func add(content: String, meeting: MeetingRecord, kind: String, speaker: String) {
            guard !content.isEmpty else { return }
            sqlite3_reset(insert)
            sqlite3_bind_text(insert, 1, content, -1, MeetingStore.sqliteTransient)
            sqlite3_bind_text(insert, 2, meeting.title, -1, MeetingStore.sqliteTransient)
            sqlite3_bind_int64(insert, 3, meeting.id)
            sqlite3_bind_text(insert, 4, kind, -1, MeetingStore.sqliteTransient)
            sqlite3_bind_text(insert, 5, speaker, -1, MeetingStore.sqliteTransient)
            sqlite3_bind_double(insert, 6, meeting.date.timeIntervalSince1970)
            _ = sqlite3_step(insert)
        }

        for meeting in meetings {
            for segment in try store.segments(meetingID: meeting.id) {
                add(content: segment.text, meeting: meeting, kind: "transcript", speaker: segment.speaker)
            }
            for note in try store.quickNotes(meetingID: meeting.id) {
                add(content: note.text, meeting: meeting, kind: "nota", speaker: "")
            }
            add(content: meeting.title, meeting: meeting, kind: "título", speaker: "")
        }

        var query: OpaquePointer?
        guard sqlite3_prepare_v2(db, """
        SELECT meeting_id, title, kind, speaker, date, snippet(fts, 0, '«', '»', '…', 10)
        FROM fts WHERE fts MATCH ? ORDER BY bm25(fts) LIMIT ?
        """, -1, &query, nil) == SQLITE_OK else {
            throw Self.error("Consulta inválida: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(query) }
        sqlite3_bind_text(query, 1, match, -1, MeetingStore.sqliteTransient)
        sqlite3_bind_int(query, 2, Int32(limit))

        var hits: [SearchHit] = []
        while sqlite3_step(query) == SQLITE_ROW {
            hits.append(SearchHit(
                meetingID: sqlite3_column_int64(query, 0),
                title: String(cString: sqlite3_column_text(query, 1)),
                date: Date(timeIntervalSince1970: sqlite3_column_double(query, 4)),
                kind: String(cString: sqlite3_column_text(query, 2)),
                speaker: String(cString: sqlite3_column_text(query, 3)),
                snippet: String(cString: sqlite3_column_text(query, 5))
            ))
        }
        return hits
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "aria.search", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
