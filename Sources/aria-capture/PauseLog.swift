import Foundation

struct PauseInterval: Equatable {
    let start: Date
    let end: Date
    /// Posición en el eje de tiempo activo (mismo eje que `TranscriptSegment.start`) donde
    /// ocurrió la pausa: como el audio no se grava mientras está pausado, el siguiente segmento
    /// retoma exactamente en este offset.
    let transcriptOffsetSeconds: TimeInterval

    var durationSeconds: TimeInterval { end.timeIntervalSince(start) }
}

struct PauseLog: Equatable {
    private(set) var intervals: [PauseInterval] = []
    private(set) var openPauseStart: Date?
    private var openOffset: TimeInterval = 0

    var isOpen: Bool { openPauseStart != nil }

    mutating func beginPause(at date: Date, activeOffsetSeconds: TimeInterval) {
        guard openPauseStart == nil else { return }
        openPauseStart = date
        openOffset = activeOffsetSeconds
    }

    @discardableResult
    mutating func endPause(at date: Date) -> PauseInterval? {
        guard let start = openPauseStart else { return nil }
        let interval = PauseInterval(start: start, end: date, transcriptOffsetSeconds: openOffset)
        intervals.append(interval)
        openPauseStart = nil
        openOffset = 0
        return interval
    }

    var totalPausedSeconds: TimeInterval {
        intervals.reduce(0) { $0 + $1.durationSeconds }
    }

    mutating func reset() {
        intervals = []
        openPauseStart = nil
        openOffset = 0
    }
}

enum PauseLogic {

    static let markerPrefix = "⏸ Grabación en pausa"
    static let sectionHeading = "## Pausas"

    private static func clockFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    /// "HH:MM – HH:MM (N min)", apto para frontmatter o listas compactas.
    static func rangeLabel(for interval: PauseInterval) -> String {
        let formatter = clockFormatter()
        let minutes = max(1, Int((interval.durationSeconds / 60).rounded()))
        return "\(formatter.string(from: interval.start)) – \(formatter.string(from: interval.end)) (\(minutes) min)"
    }

    /// "⏸ Grabación en pausa HH:MM – HH:MM (N min)", para insertar en el transcript.
    static func marker(for interval: PauseInterval) -> String {
        "\(markerPrefix) \(rangeLabel(for: interval))"
    }

    static func totalPausedSeconds(_ intervals: [PauseInterval]) -> TimeInterval {
        intervals.reduce(0) { $0 + $1.durationSeconds }
    }

    /// Duración real de la reunión (grabado + pausado), a partir de lo que sí quedó grabado
    /// (que ya excluye las pausas, porque no se graba audio mientras está pausado).
    static func wallClockSeconds(recordedSeconds: TimeInterval, pauses: [PauseInterval]) -> TimeInterval {
        recordedSeconds + totalPausedSeconds(pauses)
    }

    static func appendingPausesSection(to markdown: String, pauses: [PauseInterval]) -> String {
        guard !pauses.isEmpty else { return markdown }
        let base = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.contains(sectionHeading) else { return base }
        let bullets = pauses.map { "- ⏸ \(rangeLabel(for: $0))" }.joined(separator: "\n")
        return base + "\n\n" + sectionHeading + "\n" + bullets
    }
}
