import Foundation

struct ChunkingOptions {
    var windowSeconds: Double = 8
    var overlapSeconds: Double = 1
    var energyRMSThreshold: Float = 0.006
    var vadFrameSeconds: Double = 0.3
    var vadMergeGapSeconds: Double = 0.6
    var vadPadSeconds: Double = 0.25
    var minVoicedSeconds: Double = 0.4
    var minSegmentSeconds: Double = 0.35

    static let `default` = ChunkingOptions()
}

struct ChunkStats {
    var windows = 0
    var voicedSeconds: Double = 0
    var totalSeconds: Double = 0
}

final class ChunkedTranscriber {

    private let transcriber: WhisperTranscriber
    private let options: ChunkingOptions
    private let vad: VoiceActivityDetector
    private let sampleRate: Double = 16_000

    init(transcriber: WhisperTranscriber, options: ChunkingOptions = .default, vad: VoiceActivityDetector? = nil) {
        self.transcriber = transcriber
        self.options = options
        self.vad = vad ?? VADFactory.preferred(options: options)
    }

    static func merged(_ lists: [[TranscriptSegment]]) -> [TranscriptSegment] {
        coalesced(lists.flatMap { $0 }.sorted { $0.start < $1.start })
    }

    static func coalesced(_ segments: [TranscriptSegment], maxGap: TimeInterval = 1.2) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        for segment in segments {
            if let last = result.last,
               last.speaker == segment.speaker,
               segment.start - last.end <= maxGap {
                result[result.count - 1] = TranscriptSegment(
                    start: last.start,
                    end: segment.end,
                    text: joinedTurnText(last.text, segment.text),
                    speaker: last.speaker
                )
            } else {
                result.append(segment)
            }
        }
        return result
    }

    static func joinedTurnText(_ first: String, _ second: String) -> String {
        guard !first.isEmpty else { return second }
        guard !second.isEmpty else { return first }
        return first.hasSuffix("-") ? first.dropLast() + second : first + " " + second
    }

    func transcribe(samples: [Float], language: String = "es", speaker: String = "") throws -> (segments: [TranscriptSegment], stats: ChunkStats) {
        var stats = ChunkStats(totalSeconds: Double(samples.count) / sampleRate)
        var result: [TranscriptSegment] = []
        var lastEnd: TimeInterval = 0

        for region in voicedRegions(in: samples) {
            stats.voicedSeconds += Double(region.count) / sampleRate
            let window = Int(options.windowSeconds * sampleRate)
            let step = max(1, window - Int(options.overlapSeconds * sampleRate))
            var start = region.lowerBound

            while start < region.upperBound {
                let end = min(start + window, region.upperBound)
                let slice = Array(samples[start..<end])
                let offset = Double(start) / sampleRate
                let sliceEnd = Double(end) / sampleRate
                stats.windows += 1

                for segment in try transcriber.transcribe(samples: slice, language: language) {
                    let globalStart = segment.start + offset
                    let globalEnd = min(segment.end + offset, sliceEnd)
                    guard !segment.text.isEmpty, !Self.isNonSpeech(segment.text), globalEnd > lastEnd + 0.2 else { continue }
                    guard globalEnd - max(globalStart, lastEnd) >= options.minSegmentSeconds else { continue }
                    guard !Self.isHallucination(text: segment.text, duration: globalEnd - max(globalStart, lastEnd)) else { continue }

                    var segmentStart = max(globalStart, lastEnd)
                    var text = segment.text
                    if let last = result.last, last.end > offset {
                        if Self.normalized(text).hasPrefix(Self.normalized(last.text)) {
                            result.removeLast()
                            segmentStart = last.start
                        } else {
                            text = Self.strippingOverlapPrefix(text, previous: last.text)
                        }
                    }
                    guard !text.isEmpty else { continue }
                    result.append(TranscriptSegment(start: segmentStart, end: globalEnd, text: text, speaker: speaker))
                    lastEnd = globalEnd
                }

                if end == region.upperBound { break }
                start += step
            }
        }
        return (result, stats)
    }

    func voicedRegions(in samples: [Float]) -> [Range<Int>] {
        vad.voicedRegions(in: samples, sampleRate: sampleRate)
    }

    static func voicedRegions(in samples: [Float], options: ChunkingOptions, sampleRate: Double) -> [Range<Int>] {
        let frame = max(1, Int(options.vadFrameSeconds * sampleRate))
        let pad = Int(options.vadPadSeconds * sampleRate)
        let mergeGap = Int(options.vadMergeGapSeconds * sampleRate)
        let minLength = Int(options.minVoicedSeconds * sampleRate)

        var regions: [Range<Int>] = []
        var current: Range<Int>?
        var frameStart = 0

        while frameStart < samples.count {
            let frameEnd = min(frameStart + frame, samples.count)
            let active = Self.rms(samples, in: frameStart..<frameEnd) >= options.energyRMSThreshold
            if active {
                if let open = current, frameStart - open.upperBound <= mergeGap {
                    current = open.lowerBound..<frameEnd
                } else {
                    if let open = current { regions.append(open) }
                    current = frameStart..<frameEnd
                }
            }
            frameStart = frameEnd
        }
        if let open = current { regions.append(open) }

        return regions.compactMap { region in
            guard region.count >= minLength else { return nil }
            let start = max(0, region.lowerBound - pad)
            let end = min(samples.count, region.upperBound + pad)
            return start..<end
        }
    }

    static let hallucinationBlocklist = [
        "amara.org",
        "subtítulos por la comunidad",
        "subtítulos realizados por",
        "gracias por ver",
        "suscríbete"
    ]

    static func isHallucination(text: String, duration: TimeInterval) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace).count
        if Double(words) / max(duration, 0.01) > 8 { return true }
        let lowered = text.lowercased()
        return hallucinationBlocklist.contains { lowered.contains($0) }
    }

    static func strippingOverlapPrefix(_ text: String, previous: String) -> String {
        let originalWords = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let newWords = originalWords.map { normalized($0) }
        let previousWords = previous.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }
        let maxOverlap = min(previousWords.count, newWords.count, 6)

        func matches(_ old: String, _ new: String) -> Bool {
            old == new || old.hasSuffix(new) || new.hasSuffix(old)
        }

        for count in stride(from: maxOverlap, through: 1, by: -1) {
            let tail = previousWords.suffix(count)
            let head = newWords.prefix(count)
            if zip(tail, head).allSatisfy({ matches($0, $1) }) {
                return originalWords.dropFirst(count).joined(separator: " ")
            }
        }
        return text
    }

    static func isNonSpeech(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
            || (trimmed.hasPrefix("(") && trimmed.hasSuffix(")"))
    }

    static func normalized(_ text: String) -> String {
        text.lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .trimmingCharacters(in: .whitespaces)
    }

    static func rms(_ samples: [Float], in range: Range<Int>) -> Float {
        guard !range.isEmpty else { return 0 }
        var sum: Float = 0
        for index in range {
            sum += samples[index] * samples[index]
        }
        return (sum / Float(range.count)).squareRoot()
    }
}
