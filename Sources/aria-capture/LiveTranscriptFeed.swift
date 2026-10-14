import Foundation

struct LiveTranscriptLine: Equatable {
    let speaker: String
    let text: String
    let timestamp: TimeInterval
}

final class LiveTranscriptFeed {

    static let youLabel = "Tú"
    static let themLabel = "Ellos"

    private let lock = NSLock()
    private var lines: [LiveTranscriptLine] = []
    private let maxLines: Int

    init(maxLines: Int = 40) {
        self.maxLines = maxLines
    }

    func append(_ segments: [TranscriptSegment], speaker: String) {
        guard !segments.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        for segment in segments where !segment.text.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append(LiveTranscriptLine(speaker: speaker, text: segment.text, timestamp: segment.start))
        }
        lines.sort { $0.timestamp < $1.timestamp }
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    func recentLines(limit: Int) -> [LiveTranscriptLine] {
        lock.lock()
        defer { lock.unlock() }
        guard limit > 0, !lines.isEmpty else { return [] }
        return Array(lines.suffix(limit))
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        lines.removeAll()
    }

    static func formatted(_ lines: [LiveTranscriptLine]) -> String {
        lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    static func speakerLabel(forTrack track: AudioTrack) -> String {
        track == .mic ? youLabel : themLabel
    }
}

enum AudioTrack {
    case mic
    case system
}
