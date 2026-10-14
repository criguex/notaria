import Foundation

enum MeetingSourceFilter: String, CaseIterable, Identifiable {
    case all
    case native
    case imported

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Todas"
        case .native: return "Nativas"
        case .imported: return "Importadas"
        }
    }

    func matches(_ record: MeetingRecord) -> Bool {
        switch self {
        case .all: return true
        case .native: return record.source == "aria"
        case .imported: return record.source != "aria"
        }
    }
}

struct MeetingDaySection: Identifiable, Equatable {
    let day: Date
    let records: [MeetingRecord]
    var id: TimeInterval { day.timeIntervalSince1970 }

    static func == (lhs: MeetingDaySection, rhs: MeetingDaySection) -> Bool {
        lhs.day == rhs.day && lhs.records.map(\.id) == rhs.records.map(\.id)
    }
}

extension MeetingRecord: Identifiable {}

enum MeetingHistoryViewModel {

    static func filtered(_ records: [MeetingRecord], source: MeetingSourceFilter) -> [MeetingRecord] {
        records.filter(source.matches)
    }

    static func grouped(_ records: [MeetingRecord], calendar: Calendar = .current) -> [MeetingDaySection] {
        let sorted = records.sorted { $0.date > $1.date }
        var order: [Date] = []
        var buckets: [Date: [MeetingRecord]] = [:]
        for record in sorted {
            let day = calendar.startOfDay(for: record.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(record)
        }
        return order.map { MeetingDaySection(day: $0, records: buckets[$0] ?? []) }
    }

    static func meetingIDOrder(fromHits hits: [SearchHit]) -> [Int64] {
        var seen = Set<Int64>()
        var order: [Int64] = []
        for hit in hits where !seen.contains(hit.meetingID) {
            seen.insert(hit.meetingID)
            order.append(hit.meetingID)
        }
        return order
    }

    static func visibleRecords(
        all: [MeetingRecord],
        source: MeetingSourceFilter,
        searchHitsOrder: [Int64]?
    ) -> [MeetingRecord] {
        let bySource = filtered(all, source: source)
        guard let searchHitsOrder else { return bySource }
        let byID = Dictionary(uniqueKeysWithValues: bySource.map { ($0.id, $0) })
        return searchHitsOrder.compactMap { byID[$0] }
    }
}

struct ChatTurn: Identifiable, Equatable {
    let id = UUID()
    let question: String
    var answer: String
    var isError = false
}

enum ChatSessionLogic {

    static func trimmedQuestion(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func appendingQuestion(_ turns: [ChatTurn], question: String) -> [ChatTurn] {
        turns + [ChatTurn(question: question, answer: "")]
    }

    static func appendingChunk(_ turns: [ChatTurn], chunk: String, at index: Int) -> [ChatTurn] {
        guard turns.indices.contains(index) else { return turns }
        var copy = turns
        copy[index].answer += chunk
        return copy
    }

    static func markError(_ turns: [ChatTurn], at index: Int, message: String) -> [ChatTurn] {
        guard turns.indices.contains(index) else { return turns }
        var copy = turns
        copy[index].answer = "[error] \(message)"
        copy[index].isError = true
        return copy
    }
}
