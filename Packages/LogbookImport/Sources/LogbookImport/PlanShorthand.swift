import Foundation
import LogbookCore

/// A task typed as `t write SIH deck ~45m !! fri #horizon every mon`.
public struct ParsedTask: Hashable, Sendable {
    public var title: String
    public var estimateMinutes: Int?
    /// 0 none, 1 `!`, 2 `!!`.
    public var priority: Int
    public var listName: String?
    /// Deadline (`fri`, `tomorrow`, `12 nov`, `2026-11-12`).
    public var due: LogicalDay?
    /// When you intend to do it (`@tomorrow`, `@fri`).
    public var scheduled: LogicalDay?
    public var someday: Bool
    public var recurrence: Recurrence?
}

/// A planned block typed as `plan tomorrow 1400-1600 deep work`.
public struct ParsedPlan: Hashable, Sendable {
    public var day: LogicalDay
    public var kind: BlockKind
    public var start: WallTime
    public var end: WallTime
    public var label: String
}

public enum PlanShorthand {
    static let weekdayNames: [String: Int] = [
        "mon": 1, "monday": 1, "tue": 2, "tues": 2, "tuesday": 2, "wed": 3, "wednesday": 3,
        "thu": 4, "thur": 4, "thurs": 4, "thursday": 4, "fri": 5, "friday": 5,
        "sat": 6, "saturday": 6, "sun": 7, "sunday": 7,
    ]

    /// `today`, `tomorrow`, a weekday (the next one, today included), or a date.
    static func day(_ token: String, today: LogicalDay) -> LogicalDay? {
        let t = token.lowercased()
        switch t {
        case "today", "tod": return today
        case "tomorrow", "tmrw", "tmr", "tom": return today.next
        default: break
        }
        if let wd = weekdayNames[t] {
            return today.adding(days: (wd - today.isoWeekday + 7) % 7)
        }
        return DateHeader.parse(token, previous: today, defaultYear: today.year)
    }

    // MARK: Tasks

    /// Parses the text after `t `.
    public static func task(_ text: String, today: LogicalDay) -> ParsedTask {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var out = ParsedTask(title: "", estimateMinutes: nil, priority: 0, listName: nil, due: nil, scheduled: nil, someday: false, recurrence: nil)
        var title: [String] = []
        var i = 0
        while i < tokens.count {
            let tok = tokens[i], lower = tok.lowercased()
            let next = i + 1 < tokens.count ? tokens[i + 1] : nil
            if tok.hasPrefix("~"), let m = Durations.parseCompact(String(tok.dropFirst())) {
                out.estimateMinutes = m
            } else if tok == "!" || tok == "!!" || tok == "!!!" {
                out.priority = min(2, tok.count)
            } else if tok.hasPrefix("#"), tok.count > 1 {
                out.listName = String(tok.dropFirst())
            } else if lower == "@someday" {
                out.someday = true
            } else if tok.hasPrefix("@"), let d = day(String(tok.dropFirst()), today: today) {
                out.scheduled = d
            } else if lower == "every" || lower == "after", let (rule, used) = recurrence(Array(tokens[(i + 1)...]), after: lower == "after") {
                out.recurrence = rule
                i += used
            } else if let next, out.due == nil, let d = DateHeader.parse("\(tok) \(next)", previous: today, defaultYear: today.year) {
                out.due = d
                i += 1
            } else if out.due == nil, isDateToken(lower), let d = day(tok, today: today) {
                out.due = d
            } else {
                title.append(tok)
            }
            i += 1
        }
        tokens = title
        out.title = tokens.joined(separator: " ")
        return out
    }

    static func isDateToken(_ t: String) -> Bool {
        ["today", "tod", "tomorrow", "tmrw", "tmr", "tom"].contains(t) || weekdayNames[t] != nil
            || t.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil || t.wholeMatch(of: /\d{1,2}[\/.]\d{1,2}[\/.]\d{2,4}/) != nil
    }

    /// `every day|weekday|week|month|mon,wed|2 weeks` or `after 3 days`.
    /// Returns the rule and how many tokens it consumed after the keyword.
    static func recurrence(_ t: [String], after: Bool) -> (Recurrence, Int)? {
        guard let first = t.first?.lowercased() else { return nil }
        func unit(_ s: String) -> Recurrence.Frequency? {
            switch s.lowercased() {
            case "day", "days", "daily": .daily
            case "week", "weeks", "weekly": .weekly
            case "month", "months", "monthly": .monthly
            default: nil
            }
        }
        if let n = Int(first), t.count > 1, let f = unit(t[1]) {
            return (Recurrence(frequency: f, interval: n, afterCompletion: after), 2)
        }
        if after { return nil }
        if first == "weekday" || first == "weekdays" {
            return (Recurrence(frequency: .weekly, weekdays: [1, 2, 3, 4, 5]), 1)
        }
        if let f = unit(first) { return (Recurrence(frequency: f), 1) }
        let days = first.split(separator: ",").compactMap { weekdayNames[String($0)] }
        if !days.isEmpty, days.count == first.split(separator: ",").count {
            return (Recurrence(frequency: .weekly, weekdays: days), 1)
        }
        return nil
    }

    // MARK: Plan blocks

    static let planKinds: [String: BlockKind] = [
        "work": .work, "sleep": .sleep, "nc": .natureCall,
        "break": BlockKind(rawValue: "break"), "gym": BlockKind(rawValue: "gym"),
    ]

    /// Parses the text after `plan `: `[day] [kind] HHMM-HHMM label`.
    public static func plan(_ text: String, today: LogicalDay) -> ParsedPlan? {
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var d = today
        if let first = tokens.first, isDateToken(first.lowercased()), let parsed = day(first, today: today) {
            d = parsed
            tokens.removeFirst()
        }
        var kind = BlockKind.work
        if let first = tokens.first, let k = planKinds[first.lowercased()] {
            kind = k
            tokens.removeFirst()
        }
        guard let r = ShorthandParser.range(tokens.joined(separator: " ")) else { return nil }
        var block = ShorthandParser.forwardBlock(kind, r, on: d, label: r.label)
        if kind == .sleep, r.start < r.end, r.start < 12 * 60 {
            // "plan sleep 0100-0900" means the night after `d`.
            block.start.day = d.next
            block.end.day = d.next
        }
        return ParsedPlan(day: d, kind: kind, start: block.start, end: block.end, label: r.label)
    }
}
