import Foundation

enum MeetingNotepadLogic {

    static let ownNotesHeading = "## Notas propias"

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func draftFileName(for since: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return "\(formatter.string(from: since)) notas.md"
    }

    static func draftURL(for since: Date, in directory: URL) -> URL {
        directory.appendingPathComponent(draftFileName(for: since))
    }

    static func mergedOwnNotes(_ pieces: String...) -> String {
        pieces.map(trimmed).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func appendingOwnNotesSection(to markdown: String, ownNotes: String) -> String {
        let notes = trimmed(ownNotes)
        let base = trimmed(markdown)
        guard !notes.isEmpty, !base.contains(ownNotesHeading) else { return base }
        return base + "\n\n" + ownNotesHeading + "\n" + notes
    }
}

final class NotepadFileStore {

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func save(_ text: String) throws {
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}

@MainActor
final class MeetingNotepadController: ObservableObject {

    @Published var text: String = ""
    @Published private(set) var isActive = false

    private let directory: URL
    private var store: NotepadFileStore?
    private var debounceTimer: Timer?
    private var flushTimer: Timer?

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Aria/Grabaciones", isDirectory: true)
    }

    func begin(since: Date) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = NotepadFileStore(fileURL: MeetingNotepadLogic.draftURL(for: since, in: directory))
        self.store = store
        text = store.load()
        isActive = true
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.persist() }
        }
    }

    func noteChanged() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.persist() }
        }
    }

    func persist() {
        guard let store else { return }
        try? store.save(text)
    }

    @discardableResult
    func finish() -> String {
        persist()
        let result = text
        try? store?.clear()
        invalidateTimers()
        store = nil
        isActive = false
        text = ""
        return result
    }

    func reset() {
        invalidateTimers()
        store = nil
        isActive = false
        text = ""
    }

    private func invalidateTimers() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        flushTimer?.invalidate()
        flushTimer = nil
    }

    deinit {
        debounceTimer?.invalidate()
        flushTimer?.invalidate()
    }
}
