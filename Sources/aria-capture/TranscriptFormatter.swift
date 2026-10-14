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

    /// Igual que `render(_:)` pero intercala los marcadores de pausa en el punto correcto del
    /// eje de tiempo activo (mismo eje que `segment.start`, ya que no se graba audio en pausa).
    static func render(_ segments: [TranscriptSegment], pauses: [PauseInterval]) -> String {
        guard !pauses.isEmpty else { return render(segments) }
        var items: [(offset: TimeInterval, isPause: Bool, text: String)] =
            segments.map { (offset: $0.start, isPause: false, text: line($0)) }
        items += pauses.map { (offset: $0.transcriptOffsetSeconds, isPause: true, text: PauseLogic.marker(for: $0)) }
        items.sort { lhs, rhs in
            if lhs.offset != rhs.offset { return lhs.offset < rhs.offset }
            return lhs.isPause && !rhs.isPause
        }
        return items.map(\.text).joined(separator: "\n")
    }
}
