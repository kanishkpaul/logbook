import Foundation
import LogbookCore
import LogbookPersistence

/// A week of what actually happened: blocks split into per-day parts.
public struct WeekState: Equatable {
    public var days: [Column]
    public var items: [Item]
    public var title: String

    public struct Column: Equatable, Identifiable {
        public var day: LogicalDay
        /// "Mon 9"
        public var label: String
        public var summary: String
        public var isToday: Bool
        public var id: LogicalDay { day }
    }

    public struct Item: Equatable, Identifiable {
        public var id: String
        public var column: String
        public var domain: Domain
        public var startMinute: Double
        public var endMinute: Double
        public var label: String
        /// A planned block (drawn ghosted behind what happened).
        public var isPlan: Bool = false
    }
}

/// A month grid of days with their headline numbers.
public struct MonthState: Equatable {
    public var title: String
    /// Leading `nil`s pad the first week (weeks start on Monday).
    public var cells: [Cell?]

    public struct Cell: Equatable, Identifiable {
        public var day: LogicalDay
        public var number: Int
        public var lines: [String]
        public var isToday: Bool
        public var hasData: Bool
        public var id: LogicalDay { day }
    }
}

public struct CalendarPresenter {
    public var timeZone: TimeZone

    public init(timeZone: TimeZone) {
        self.timeZone = timeZone
    }

    /// The Monday on or before `day`.
    public static func weekStart(_ day: LogicalDay) -> LogicalDay {
        // 1970-01-01 was a Thursday; Monday = 0.
        let weekday = ((day.daysSinceEpoch % 7) + 7 + 3) % 7
        return day.adding(days: -weekday)
    }

    public static func monthBounds(_ day: LogicalDay) -> (first: LogicalDay, last: LogicalDay) {
        let first = LogicalDay(year: day.year, month: day.month, day: 1)!
        let next = day.month == 12 ? LogicalDay(year: day.year + 1, month: 1, day: 1)! : LogicalDay(year: day.year, month: day.month + 1, day: 1)!
        return (first, next.previous)
    }

    func formatter(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_GB")
        d.timeZone = timeZone
        d.dateFormat = f
        return d
    }

    func noon(_ day: LogicalDay) -> Date {
        DayBoundary.calendarDay.start(of: day, in: timeZone).addingTimeInterval(12 * 3600)
    }

    static func summary(_ f: DailyFacts) -> [String] {
        var lines: [String] = []
        if let w = f.workMin { lines.append("work \(Durations.compact(minutes: w))") }
        if let s = f.sleepMin { lines.append("sleep \(Durations.compact(minutes: s))") }
        if let k = f.kcal { lines.append("\(NutritionFormat.whole(k)) kcal") }
        return lines
    }

    public func week(_ r: RangeSnapshot, today: LogicalDay) -> WeekState {
        let label = formatter("EEE d")
        let columns = r.facts.map { f in
            WeekState.Column(day: f.logicalDay, label: label.string(from: noon(f.logicalDay)),
                             summary: Self.summary(f).joined(separator: " · "), isToday: f.logicalDay == today)
        }
        let labels = Dictionary(uniqueKeysWithValues: columns.map { ($0.day, $0.label) })
        let items = r.blocks.flatMap { b -> [WeekState.Item] in
            guard let end = b.endUTC else { return [] }
            let domain = Domain(kind: b.kind) ?? .work
            return DayPart.parts(start: b.startUTC, end: end, in: timeZone).compactMap { p in
                guard let column = labels[p.day] else { return nil }
                return .init(id: "\(b.id)-\(p.day)", column: column, domain: domain,
                             startMinute: p.startMinute, endMinute: p.endMinute, label: b.label)
            }
        }
        let planned = r.plans.filter { $0.status != .skipped }.flatMap { p -> [WeekState.Item] in
            let domain = Domain(kind: p.kind) ?? .work
            return DayPart.parts(start: p.startUTC, end: p.endUTC, in: timeZone).compactMap { part in
                guard let column = labels[part.day] else { return nil }
                return .init(id: "plan-\(p.id)-\(part.day)", column: column, domain: domain,
                             startMinute: part.startMinute, endMinute: part.endMinute, label: p.label, isPlan: true)
            }
        }
        let title = "\(formatter("d MMM").string(from: noon(r.first))) – \(formatter("d MMM yyyy").string(from: noon(r.last)))"
        return WeekState(days: columns, items: planned + items, title: title)
    }

    public func month(_ r: RangeSnapshot, today: LogicalDay) -> MonthState {
        let lead = r.first.daysSinceEpoch - Self.weekStart(r.first).daysSinceEpoch
        let cells: [MonthState.Cell?] = Array(repeating: nil, count: lead) + r.facts.map { f in
            .init(day: f.logicalDay, number: f.logicalDay.day, lines: Self.summary(f),
                  isToday: f.logicalDay == today, hasData: !f.isEmpty)
        }
        return MonthState(title: formatter("MMMM yyyy").string(from: noon(r.first)), cells: cells)
    }
}
