import Foundation

/// A subset of iCalendar RRULE for repeating tasks and plan blocks.
///
/// Supported: `FREQ=DAILY|WEEKLY|MONTHLY`, `INTERVAL=n`, `BYDAY=MO,TU,…`
/// (weekly only). The non-standard prefix `AFTER;` means "count from the day
/// it was completed" instead of from the schedule (e.g. water the plants 3
/// days after you last did). Everything works on logical days, so DST and
/// time zones never shift a repeat.
public struct Recurrence: Hashable, Sendable, CustomStringConvertible {
    public enum Frequency: String, Sendable { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY" }

    public var frequency: Frequency
    public var interval: Int
    /// ISO weekdays, Monday = 1 … Sunday = 7 (weekly only).
    public var weekdays: [Int]
    public var afterCompletion: Bool

    public init(frequency: Frequency, interval: Int = 1, weekdays: [Int] = [], afterCompletion: Bool = false) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays.sorted()
        self.afterCompletion = afterCompletion
    }

    static let dayCodes = ["MO": 1, "TU": 2, "WE": 3, "TH": 4, "FR": 5, "SA": 6, "SU": 7]

    /// Parses `FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE` (optionally prefixed `AFTER;`).
    public init?(rule: String) {
        var parts = rule.uppercased().split(separator: ";").map(String.init)
        var after = false
        if parts.first == "AFTER" {
            after = true
            parts.removeFirst()
        }
        var freq: Frequency?
        var interval = 1
        var days: [Int] = []
        for p in parts {
            let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { return nil }
            switch kv[0] {
            case "FREQ": freq = Frequency(rawValue: kv[1])
            case "INTERVAL": guard let n = Int(kv[1]), n > 0 else { return nil }; interval = n
            case "BYDAY":
                for code in kv[1].split(separator: ",") {
                    guard let d = Self.dayCodes[String(code)] else { return nil }
                    days.append(d)
                }
            default: return nil
            }
        }
        guard let freq else { return nil }
        if !days.isEmpty && freq != .weekly { return nil }
        self.init(frequency: freq, interval: interval, weekdays: days, afterCompletion: after)
    }

    /// The canonical rule text (round-trips through `init(rule:)`).
    public var description: String {
        var parts = ["FREQ=\(frequency.rawValue)"]
        if interval != 1 { parts.append("INTERVAL=\(interval)") }
        if !weekdays.isEmpty {
            let codes = Dictionary(uniqueKeysWithValues: Self.dayCodes.map { ($1, $0) })
            parts.append("BYDAY=" + weekdays.map { codes[$0]! }.joined(separator: ","))
        }
        return (afterCompletion ? "AFTER;" : "") + parts.joined(separator: ";")
    }

    /// The next occurrence strictly after `day`, for a series anchored at
    /// `anchor` (the first occurrence). For `afterCompletion`, pass the
    /// completion day as `day`; the anchor is ignored.
    public func next(after day: LogicalDay, anchor: LogicalDay) -> LogicalDay {
        if afterCompletion {
            switch frequency {
            case .daily: return day.adding(days: interval)
            case .weekly: return day.adding(days: 7 * interval)
            case .monthly: return Self.addMonths(day, interval)
            }
        }
        switch frequency {
        case .daily:
            let delta = anchor.days(to: day)
            guard delta >= 0 else { return anchor }
            return anchor.adding(days: (delta / interval + 1) * interval)
        case .weekly:
            let days = weekdays.isEmpty ? [anchor.isoWeekday] : weekdays
            let anchorWeek = anchor.adding(days: -(anchor.isoWeekday - 1))
            var candidate = max(day.next, anchor)
            for _ in 0..<(7 * interval * 2 + 7) {
                let weeks = anchorWeek.days(to: candidate.adding(days: -(candidate.isoWeekday - 1))) / 7
                if weeks % interval == 0, days.contains(candidate.isoWeekday) { return candidate }
                candidate = candidate.next
            }
            return candidate
        case .monthly:
            var n = 0
            var candidate = anchor
            while candidate <= day {
                n += interval
                candidate = Self.addMonths(anchor, n)
            }
            return candidate
        }
    }

    /// Same day-of-month `n` months later, clamped to the month's last day.
    static func addMonths(_ day: LogicalDay, _ n: Int) -> LogicalDay {
        let total = day.year * 12 + (day.month - 1) + n
        let y = total / 12, m = total % 12 + 1
        let last = LogicalDay.daysInMonth(year: y, month: m)
        return LogicalDay(year: y, month: m, day: min(day.day, last))!
    }

    /// "every day", "every 2 weeks on Mon, Wed", "3 days after done".
    public var summary: String {
        let names = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let unit: String = switch frequency {
        case .daily: interval == 1 ? "day" : "\(interval) days"
        case .weekly: interval == 1 ? "week" : "\(interval) weeks"
        case .monthly: interval == 1 ? "month" : "\(interval) months"
        }
        if afterCompletion { return "\(unit) after done" }
        if frequency == .weekly, weekdays == [1, 2, 3, 4, 5], interval == 1 { return "every weekday" }
        var s = "every \(unit)"
        if !weekdays.isEmpty { s += " on " + weekdays.map { names[$0] }.joined(separator: ", ") }
        return s
    }
}

extension LogicalDay {
    /// Monday = 1 … Sunday = 7.
    public var isoWeekday: Int {
        // 1970-01-01 was a Thursday (4).
        ((daysSinceEpoch % 7) + 7 + 3) % 7 + 1
    }
}
