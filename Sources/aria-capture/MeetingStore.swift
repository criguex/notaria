import Foundation
import SQLite3

struct MeetingRecord {
    let id: Int64
    let date: Date
    let title: String
    let durationSeconds: Double
    let notePath: String
    let wavPath: String?
    var source: String = "aria"
    var externalID: String? = nil
}

struct VisualCaptureRow {
    let id: Int64
    let meetingID: Int64
    let elapsedSeconds: Double
    let ocrText: String
    let imagePath: String
}

final class MeetingStore {

    static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var db: OpaquePointer?
    private let cipher: CacheCipher

    init(databaseURL: URL? = nil) throws {
        cipher = try CacheCipher()
        let url = databaseURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Aria/aria.db")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw Self.error(db, context: "abriendo la base")
        }
        sqlite3_busy_timeout(db, 3_000)
        try execute("""
        CREATE TABLE IF NOT EXISTS meetings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date REAL NOT NULL,
            title TEXT NOT NULL,
            duration REAL NOT NULL,
            note_path TEXT NOT NULL,
            wav_path TEXT
        );
        CREATE TABLE IF NOT EXISTS segments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            meeting_id INTEGER NOT NULL REFERENCES meetings(id),
            start REAL NOT NULL,
            end REAL NOT NULL,
            speaker TEXT NOT NULL,
            text TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            meeting_id INTEGER NOT NULL REFERENCES meetings(id),
            timestamp TEXT NOT NULL,
            text TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS pauses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            meeting_id INTEGER NOT NULL REFERENCES meetings(id),
            start REAL NOT NULL,
            end REAL NOT NULL,
            offset_seconds REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS visual_captures (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            meeting_id INTEGER NOT NULL REFERENCES meetings(id),
            elapsed_seconds REAL NOT NULL,
            ocr_text TEXT NOT NULL,
            image_path TEXT NOT NULL
        );
        """)
        try migrateSchemaIfNeeded()
    }

    private func migrateSchemaIfNeeded() throws {
        var hasSource = false
        var hasExternalID = false
        var hasOwnNotes = false
        let pragma = try prepare("PRAGMA table_info(meetings)")
        defer { sqlite3_finalize(pragma) }
        while sqlite3_step(pragma) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(pragma, 1))
            if name == "source" { hasSource = true }
            if name == "external_id" { hasExternalID = true }
            if name == "own_notes" { hasOwnNotes = true }
        }
        if !hasSource {
            try execute("ALTER TABLE meetings ADD COLUMN source TEXT NOT NULL DEFAULT 'aria'")
        }
        if !hasExternalID {
            try execute("ALTER TABLE meetings ADD COLUMN external_id TEXT")
        }
        if !hasOwnNotes {
            try execute("ALTER TABLE meetings ADD COLUMN own_notes TEXT NOT NULL DEFAULT ''")
        }
        try execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_meetings_external_id ON meetings(external_id)")
    }

    deinit {
        sqlite3_close(db)
    }

    @discardableResult
    func saveMeeting(
        date: Date,
        title: String,
        durationSeconds: Double,
        notePath: String,
        wavPath: String?,
        segments: [TranscriptSegment],
        quickNotes: [QuickNote],
        ownNotes: String = "",
        pauses: [PauseInterval] = []
    ) throws -> Int64 {
        try execute("BEGIN")
        do {
            let insert = try prepare(
                "INSERT INTO meetings (date, title, duration, note_path, wav_path, own_notes) VALUES (?, ?, ?, ?, ?, ?)"
            )
            defer { sqlite3_finalize(insert) }
            sqlite3_bind_double(insert, 1, date.timeIntervalSince1970)
            sqlite3_bind_text(insert, 2, cipher.encrypt(title), -1, Self.sqliteTransient)
            sqlite3_bind_double(insert, 3, durationSeconds)
            sqlite3_bind_text(insert, 4, notePath, -1, Self.sqliteTransient)
            if let wavPath {
                sqlite3_bind_text(insert, 5, wavPath, -1, Self.sqliteTransient)
            } else {
                sqlite3_bind_null(insert, 5)
            }
            sqlite3_bind_text(insert, 6, cipher.encrypt(ownNotes), -1, Self.sqliteTransient)
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw Self.error(db, context: "insertando meeting")
            }
            let meetingID = sqlite3_last_insert_rowid(db)

            try insertSegments(segments, meetingID: meetingID)
            try insertQuickNotes(quickNotes, meetingID: meetingID)
            try insertPauses(pauses, meetingID: meetingID)

            try execute("COMMIT")
            return meetingID
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    @discardableResult
    func purge(olderThanDays days: Int) throws -> Int {
        guard days > 0 else { return 0 }
        let cutoff = Date().timeIntervalSince1970 - Double(days) * 86_400
        try execute("""
        DELETE FROM segments WHERE meeting_id IN (SELECT id FROM meetings WHERE date < \(cutoff));
        DELETE FROM notes WHERE meeting_id IN (SELECT id FROM meetings WHERE date < \(cutoff));
        DELETE FROM pauses WHERE meeting_id IN (SELECT id FROM meetings WHERE date < \(cutoff));
        DELETE FROM meetings WHERE date < \(cutoff);
        """)
        return Int(sqlite3_changes(db))
    }

    func recentMeetings(limit: Int = 10) throws -> [MeetingRecord] {
        let query = try prepare(
            "SELECT id, date, title, duration, note_path, wav_path, source, external_id FROM meetings ORDER BY date DESC LIMIT ?"
        )
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int(query, 1, Int32(limit))

        var records: [MeetingRecord] = []
        while sqlite3_step(query) == SQLITE_ROW {
            records.append(MeetingRecord(
                id: sqlite3_column_int64(query, 0),
                date: Date(timeIntervalSince1970: sqlite3_column_double(query, 1)),
                title: cipher.decrypt(String(cString: sqlite3_column_text(query, 2))),
                durationSeconds: sqlite3_column_double(query, 3),
                notePath: String(cString: sqlite3_column_text(query, 4)),
                wavPath: sqlite3_column_text(query, 5).map { String(cString: $0) },
                source: sqlite3_column_text(query, 6).map { String(cString: $0) } ?? "aria",
                externalID: sqlite3_column_text(query, 7).map { String(cString: $0) }
            ))
        }
        return records
    }

    func existingImportedMeeting(externalID: String) throws -> (id: Int64, notePath: String)? {
        let query = try prepare("SELECT id, note_path FROM meetings WHERE external_id = ? LIMIT 1")
        defer { sqlite3_finalize(query) }
        sqlite3_bind_text(query, 1, externalID, -1, Self.sqliteTransient)
        guard sqlite3_step(query) == SQLITE_ROW else { return nil }
        return (sqlite3_column_int64(query, 0), String(cString: sqlite3_column_text(query, 1)))
    }

    @discardableResult
    func upsertImportedMeeting(
        externalID: String,
        source: String,
        date: Date,
        title: String,
        durationSeconds: Double,
        notePath: String,
        segments: [TranscriptSegment],
        quickNotes: [QuickNote]
    ) throws -> Int64 {
        try execute("BEGIN")
        do {
            let existing = try existingImportedMeeting(externalID: externalID)
            let meetingID: Int64
            if let existing {
                meetingID = existing.id
                let update = try prepare(
                    "UPDATE meetings SET date = ?, title = ?, duration = ?, note_path = ?, source = ? WHERE id = ?"
                )
                defer { sqlite3_finalize(update) }
                sqlite3_bind_double(update, 1, date.timeIntervalSince1970)
                sqlite3_bind_text(update, 2, cipher.encrypt(title), -1, Self.sqliteTransient)
                sqlite3_bind_double(update, 3, durationSeconds)
                sqlite3_bind_text(update, 4, notePath, -1, Self.sqliteTransient)
                sqlite3_bind_text(update, 5, source, -1, Self.sqliteTransient)
                sqlite3_bind_int64(update, 6, meetingID)
                guard sqlite3_step(update) == SQLITE_DONE else {
                    throw Self.error(db, context: "actualizando meeting importado")
                }
                try execute("DELETE FROM segments WHERE meeting_id = \(meetingID)")
                try execute("DELETE FROM notes WHERE meeting_id = \(meetingID)")
            } else {
                let insert = try prepare(
                    "INSERT INTO meetings (date, title, duration, note_path, wav_path, source, external_id) VALUES (?, ?, ?, ?, NULL, ?, ?)"
                )
                defer { sqlite3_finalize(insert) }
                sqlite3_bind_double(insert, 1, date.timeIntervalSince1970)
                sqlite3_bind_text(insert, 2, cipher.encrypt(title), -1, Self.sqliteTransient)
                sqlite3_bind_double(insert, 3, durationSeconds)
                sqlite3_bind_text(insert, 4, notePath, -1, Self.sqliteTransient)
                sqlite3_bind_text(insert, 5, source, -1, Self.sqliteTransient)
                sqlite3_bind_text(insert, 6, externalID, -1, Self.sqliteTransient)
                guard sqlite3_step(insert) == SQLITE_DONE else {
                    throw Self.error(db, context: "insertando meeting importado")
                }
                meetingID = sqlite3_last_insert_rowid(db)
            }

            try insertSegments(segments, meetingID: meetingID)
            try insertQuickNotes(quickNotes, meetingID: meetingID)

            try execute("COMMIT")
            return meetingID
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func insertSegments(_ segments: [TranscriptSegment], meetingID: Int64) throws {
        guard !segments.isEmpty else { return }
        let segmentInsert = try prepare(
            "INSERT INTO segments (meeting_id, start, end, speaker, text) VALUES (?, ?, ?, ?, ?)"
        )
        defer { sqlite3_finalize(segmentInsert) }
        for segment in segments {
            sqlite3_reset(segmentInsert)
            sqlite3_bind_int64(segmentInsert, 1, meetingID)
            sqlite3_bind_double(segmentInsert, 2, segment.start)
            sqlite3_bind_double(segmentInsert, 3, segment.end)
            sqlite3_bind_text(segmentInsert, 4, segment.speaker, -1, Self.sqliteTransient)
            sqlite3_bind_text(segmentInsert, 5, cipher.encrypt(segment.text), -1, Self.sqliteTransient)
            guard sqlite3_step(segmentInsert) == SQLITE_DONE else {
                throw Self.error(db, context: "insertando segmento")
            }
        }
    }

    private func insertQuickNotes(_ quickNotes: [QuickNote], meetingID: Int64) throws {
        guard !quickNotes.isEmpty else { return }
        let noteInsert = try prepare(
            "INSERT INTO notes (meeting_id, timestamp, text) VALUES (?, ?, ?)"
        )
        defer { sqlite3_finalize(noteInsert) }
        for note in quickNotes {
            sqlite3_reset(noteInsert)
            sqlite3_bind_int64(noteInsert, 1, meetingID)
            sqlite3_bind_text(noteInsert, 2, note.timestamp, -1, Self.sqliteTransient)
            sqlite3_bind_text(noteInsert, 3, cipher.encrypt(note.text), -1, Self.sqliteTransient)
            guard sqlite3_step(noteInsert) == SQLITE_DONE else {
                throw Self.error(db, context: "insertando nota rápida")
            }
        }
    }

    private func insertPauses(_ pauses: [PauseInterval], meetingID: Int64) throws {
        guard !pauses.isEmpty else { return }
        let insert = try prepare(
            "INSERT INTO pauses (meeting_id, start, end, offset_seconds) VALUES (?, ?, ?, ?)"
        )
        defer { sqlite3_finalize(insert) }
        for pause in pauses {
            sqlite3_reset(insert)
            sqlite3_bind_int64(insert, 1, meetingID)
            sqlite3_bind_double(insert, 2, pause.start.timeIntervalSince1970)
            sqlite3_bind_double(insert, 3, pause.end.timeIntervalSince1970)
            sqlite3_bind_double(insert, 4, pause.transcriptOffsetSeconds)
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw Self.error(db, context: "insertando pausa")
            }
        }
    }

    func pauses(meetingID: Int64) throws -> [PauseInterval] {
        let query = try prepare(
            "SELECT start, end, offset_seconds FROM pauses WHERE meeting_id = ? ORDER BY start"
        )
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int64(query, 1, meetingID)

        var result: [PauseInterval] = []
        while sqlite3_step(query) == SQLITE_ROW {
            result.append(PauseInterval(
                start: Date(timeIntervalSince1970: sqlite3_column_double(query, 0)),
                end: Date(timeIntervalSince1970: sqlite3_column_double(query, 1)),
                transcriptOffsetSeconds: sqlite3_column_double(query, 2)
            ))
        }
        return result
    }

    func segments(meetingID: Int64) throws -> [TranscriptSegment] {
        let query = try prepare(
            "SELECT start, end, speaker, text FROM segments WHERE meeting_id = ? ORDER BY start"
        )
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int64(query, 1, meetingID)

        var result: [TranscriptSegment] = []
        while sqlite3_step(query) == SQLITE_ROW {
            result.append(TranscriptSegment(
                start: sqlite3_column_double(query, 0),
                end: sqlite3_column_double(query, 1),
                text: cipher.decrypt(String(cString: sqlite3_column_text(query, 3))),
                speaker: String(cString: sqlite3_column_text(query, 2))
            ))
        }
        return result
    }

    func quickNotes(meetingID: Int64) throws -> [QuickNote] {
        let query = try prepare(
            "SELECT timestamp, text FROM notes WHERE meeting_id = ? ORDER BY id"
        )
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int64(query, 1, meetingID)

        var result: [QuickNote] = []
        while sqlite3_step(query) == SQLITE_ROW {
            result.append(QuickNote(
                timestamp: String(cString: sqlite3_column_text(query, 0)),
                text: cipher.decrypt(String(cString: sqlite3_column_text(query, 1)))
            ))
        }
        return result
    }

    func ownNotes(meetingID: Int64) throws -> String {
        let query = try prepare("SELECT own_notes FROM meetings WHERE id = ?")
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int64(query, 1, meetingID)
        guard sqlite3_step(query) == SQLITE_ROW, let text = sqlite3_column_text(query, 0) else { return "" }
        return cipher.decrypt(String(cString: text))
    }

    func setOwnNotes(_ text: String, meetingID: Int64) throws {
        let update = try prepare("UPDATE meetings SET own_notes = ? WHERE id = ?")
        defer { sqlite3_finalize(update) }
        sqlite3_bind_text(update, 1, cipher.encrypt(text), -1, Self.sqliteTransient)
        sqlite3_bind_int64(update, 2, meetingID)
        guard sqlite3_step(update) == SQLITE_DONE else {
            throw Self.error(db, context: "actualizando notas propias")
        }
    }

    func updateSegmentText(meetingID: Int64, segmentIndex: Int, newText: String) throws {
        let segments = try segments(meetingID: meetingID)
        guard segmentIndex >= 0 && segmentIndex < segments.count else {
            throw NSError(domain: "aria.segment", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Índice de segmento inválido"])
        }
        let segment = segments[segmentIndex]
        let update = try prepare(
            "UPDATE segments SET text = ? WHERE meeting_id = ? AND start = ? AND end = ? AND speaker = ?"
        )
        defer { sqlite3_finalize(update) }
        sqlite3_bind_text(update, 1, cipher.encrypt(newText), -1, Self.sqliteTransient)
        sqlite3_bind_int64(update, 2, meetingID)
        sqlite3_bind_double(update, 3, segment.start)
        sqlite3_bind_double(update, 4, segment.end)
        sqlite3_bind_text(update, 5, segment.speaker, -1, Self.sqliteTransient)
        guard sqlite3_step(update) == SQLITE_DONE else {
            throw Self.error(db, context: "actualizando texto del segmento")
        }
    }

    func renameSpeaker(meetingID: Int64, oldSpeaker: String, newSpeaker: String) throws {
        let update = try prepare(
            "UPDATE segments SET speaker = ? WHERE meeting_id = ? AND speaker = ?"
        )
        defer { sqlite3_finalize(update) }
        sqlite3_bind_text(update, 1, newSpeaker, -1, Self.sqliteTransient)
        sqlite3_bind_int64(update, 2, meetingID)
        sqlite3_bind_text(update, 3, oldSpeaker, -1, Self.sqliteTransient)
        guard sqlite3_step(update) == SQLITE_DONE else {
            throw Self.error(db, context: "renombrando hablante")
        }
    }

    func insertVisualCaptures(
        _ captures: [(elapsedSeconds: Double, ocrText: String, imagePath: String)],
        meetingID: Int64
    ) throws {
        guard !captures.isEmpty else { return }
        let insert = try prepare(
            "INSERT INTO visual_captures (meeting_id, elapsed_seconds, ocr_text, image_path) VALUES (?, ?, ?, ?)"
        )
        defer { sqlite3_finalize(insert) }
        for capture in captures {
            sqlite3_reset(insert)
            sqlite3_bind_int64(insert, 1, meetingID)
            sqlite3_bind_double(insert, 2, capture.elapsedSeconds)
            sqlite3_bind_text(insert, 3, cipher.encrypt(capture.ocrText), -1, Self.sqliteTransient)
            sqlite3_bind_text(insert, 4, capture.imagePath, -1, Self.sqliteTransient)
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw Self.error(db, context: "insertando captura visual")
            }
        }
    }

    func visualCaptures(meetingID: Int64) throws -> [VisualCaptureRow] {
        let query = try prepare(
            "SELECT id, elapsed_seconds, ocr_text, image_path FROM visual_captures WHERE meeting_id = ? ORDER BY elapsed_seconds"
        )
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int64(query, 1, meetingID)

        var result: [VisualCaptureRow] = []
        while sqlite3_step(query) == SQLITE_ROW {
            result.append(VisualCaptureRow(
                id: sqlite3_column_int64(query, 0),
                meetingID: meetingID,
                elapsedSeconds: sqlite3_column_double(query, 1),
                ocrText: cipher.decrypt(String(cString: sqlite3_column_text(query, 2))),
                imagePath: String(cString: sqlite3_column_text(query, 3))
            ))
        }
        return result
    }

    @discardableResult
    func deleteVisualCaptures(meetingID: Int64) throws -> [String] {
        let paths = try visualCaptures(meetingID: meetingID).map(\.imagePath)
        try execute("DELETE FROM visual_captures WHERE meeting_id = \(meetingID)")
        return paths
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw Self.error(db, context: "ejecutando SQL")
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Self.error(db, context: "preparando SQL")
        }
        return statement
    }

    private static func error(_ db: OpaquePointer?, context: String) -> NSError {
        NSError(domain: "aria.sqlite", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "SQLite (\(context)): \(String(cString: sqlite3_errmsg(db)))"
        ])
    }
}
