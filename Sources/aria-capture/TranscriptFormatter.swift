import Foundation

enum TranscriptFormatter {

    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    static func line(_ segment: TranscriptSegment) -> String {
        let speaker = segment.speaker.isEmpty ? "" : "\(segment.speaker): "
        return "[\(timestamp(segment.start))] \(speaker)\(segment.text)"
    }

    static func render(_ segments: [TranscriptSegment]) -> String {
        segments.map(line).joined(separator: "\n")
    }
}
