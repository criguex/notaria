import Foundation

enum MeetingRecordingLinker {

    static let overlapMarginSeconds: TimeInterval = 10 * 60
    static let minimumTitleSimilarity: Double = 0.34

    static func normalizedTitle(_ title: String) -> String {
        title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func titleWords(_ title: String) -> Set<String> {
        Set(
            normalizedTitle(title)
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }

    static func titleSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = titleWords(a)
        let wordsB = titleWords(b)
        guard !wordsA.isEmpty, !wordsB.isEmpty else {
            return normalizedTitle(a) == normalizedTitle(b) ? 1 : 0
        }
        let intersection = wordsA.intersection(wordsB).count
        return (2.0 * Double(intersection)) / Double(wordsA.count + wordsB.count)
    }

    static func recordEnd(_ record: MeetingRecord) -> Date {
        record.date.addingTimeInterval(record.durationSeconds)
    }

    static func overlapsWithMargin(
        recordStart: Date,
        recordEnd: Date,
        meetingStart: Date,
        meetingEnd: Date,
        margin: TimeInterval = overlapMarginSeconds
    ) -> Bool {
        recordStart < meetingEnd.addingTimeInterval(margin)
            && recordEnd > meetingStart.addingTimeInterval(-margin)
    }

    static func match(meeting: CalendarMeeting, in records: [MeetingRecord]) -> MeetingRecord? {
        if let eventIdentifier = meeting.eventIdentifier, !eventIdentifier.isEmpty,
           let exact = records.first(where: { $0.externalID == eventIdentifier }) {
            return exact
        }

        let candidates = records.filter { record in
            overlapsWithMargin(
                recordStart: record.date,
                recordEnd: recordEnd(record),
                meetingStart: meeting.start,
                meetingEnd: meeting.end
            )
        }
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }

        let scored = candidates.map { ($0, titleSimilarity($0.title, meeting.title)) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= minimumTitleSimilarity else {
            return nil
        }
        return best.0
    }
}
