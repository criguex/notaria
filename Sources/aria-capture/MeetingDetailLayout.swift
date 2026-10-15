import Foundation

enum MeetingDetailLayout {

    static let wideThreshold: CGFloat = 760

    static func isWide(width: CGFloat) -> Bool {
        width >= wideThreshold
    }
}

enum MeetingNoteMarkdown {

    static let transcriptCalloutMarker = "> [!note]- Transcript"

    static func summaryOnly(_ fullMarkdown: String) -> String {
        guard let range = fullMarkdown.range(of: transcriptCalloutMarker) else {
            return fullMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(fullMarkdown[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
