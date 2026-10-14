import Foundation

enum SubtitleParser {

    private static let timeLineRegex = try! NSRegularExpression(
        pattern: #"^(\d{2}):(\d{2}):(\d{2})[.,](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[.,](\d{3})"#
    )
    private static let vTagRegex = try! NSRegularExpression(pattern: #"<v\s+([^>]+)>"#)
    private static let speakerPrefixRegex = try! NSRegularExpression(
        pattern: #"^([A-Za-zÀ-ÿ0-9 ._'-]{1,60}):\s+(.*)$"#
    )

    static func parse(_ text: String) -> [TranscriptSegment] {
        let lines = text.components(separatedBy: .newlines)
        var segments: [TranscriptSegment] = []
        var index = 0
        while index < lines.count {
            guard let match = firstMatch(lines[index]) else {
                index += 1
                continue
            }
            let line = lines[index]
            let start = seconds(match, base: 1, in: line)
            let end = seconds(match, base: 5, in: line)
            index += 1
            var textLines: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                textLines.append(lines[index])
                index += 1
            }
            let (speaker, cleaned) = extractSpeaker(textLines.joined(separator: " "))
            if !cleaned.isEmpty {
                segments.append(TranscriptSegment(start: start, end: end, text: cleaned, speaker: speaker))
            }
        }
        return segments
    }

    private static func firstMatch(_ line: String) -> NSTextCheckingResult? {
        timeLineRegex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line))
    }

    private static func seconds(_ match: NSTextCheckingResult, base: Int, in line: String) -> TimeInterval {
        func group(_ offset: Int) -> Int {
            guard let range = Range(match.range(at: base + offset), in: line) else { return 0 }
            return Int(line[range]) ?? 0
        }
        let hours = group(0)
        let minutes = group(1)
        let secs = group(2)
        let millis = group(3)
        return TimeInterval(hours * 3600 + minutes * 60 + secs) + TimeInterval(millis) / 1000
    }

    private static func extractSpeaker(_ raw: String) -> (speaker: String, text: String) {
        var working = raw
        var speaker = ""
        let fullRange = NSRange(working.startIndex..<working.endIndex, in: working)
        if let match = vTagRegex.firstMatch(in: working, range: fullRange),
           let nameRange = Range(match.range(at: 1), in: working) {
            speaker = String(working[nameRange]).trimmingCharacters(in: .whitespaces)
            working = working.replacingOccurrences(of: #"<v\s+[^>]+>"#, with: "", options: .regularExpression)
        }
        working = working.replacingOccurrences(of: #"</v>"#, with: "", options: .regularExpression)
        working = working.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        working = working.trimmingCharacters(in: .whitespaces)
        if speaker.isEmpty {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            if let match = speakerPrefixRegex.firstMatch(in: working, range: range),
               let nameRange = Range(match.range(at: 1), in: working),
               let textRange = Range(match.range(at: 2), in: working) {
                speaker = String(working[nameRange]).trimmingCharacters(in: .whitespaces)
                working = String(working[textRange])
            }
        }
        return (speaker, working.trimmingCharacters(in: .whitespaces))
    }
}
