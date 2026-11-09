import Foundation
import LogbookCore

/// Recognises a line that is only a date (a day header).
///
/// Accepts `2026-10-10`, `10/10/2026`, `10.10.26` (day first), and textual
/// forms with an optional weekday: `10 Oct`, `Fri 10 Oct 2026`, `10th October
/// 2026`, `Oct 10, 2026`. Without a year, the previous header's year is used
/// (rolling over when the date would jump back more than ~6 months), else
/// `defaultYear`.
public enum DateHeader {
    public static func parse(_ text: String, previous: LogicalDay?, defaultYear: Int) -> LogicalDay? {
        let s = text.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        guard !s.isEmpty, s.count <= 40 else { return nil }

        if let m = s.wholeMatch(of: /(\d{4})-(\d{1,2})-(\d{1,2})/) {
            return LogicalDay(year: Int(m.1)!, month: Int(m.2)!, day: Int(m.3)!)
        }
        if let m = s.wholeMatch(of: /(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2}|\d{4})/) {
            var y = Int(m.3)!
            if y < 100 { y += 2000 }
            return LogicalDay(year: y, month: Int(m.2)!, day: Int(m.1)!)
        }
        return textual(s, previous: previous, defaultYear: defaultYear)
    }

    static let months: [String: Int] = {
        let names = ["january", "february", "march", "april", "may", "june", "july",
                     "august", "september", "october", "november", "december"]
        var map: [String: Int] = [:]
        for (i, n) in names.enumerated() {
            map[n] = i + 1
            map[String(n.prefix(3))] = i + 1
        }
        map["sept"] = 9
        return map
    }()

    static let weekdays: Set<String> = {
        let names = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        return Set(names + names.map { String($0.prefix(3)) } + ["tues", "thur", "thurs"])
    }()

    static func textual(_ s: String, previous: LogicalDay?, defaultYear: Int) -> LogicalDay? {
        var tokens = s.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        if let first = tokens.first, weekdays.contains(first) { tokens.removeFirst() }
        guard tokens.count == 2 || tokens.count == 3 else { return nil }

        func dayNumber(_ t: String) -> Int? {
            guard let m = t.wholeMatch(of: /(\d{1,2})(st|nd|rd|th)?/) else { return nil }
            return Int(m.1)
        }
        var day: Int?, month: Int?
        if let d = dayNumber(tokens[0]), let mo = months[tokens[1]] {
            (day, month) = (d, mo)
        } else if let mo = months[tokens[0]], let d = dayNumber(tokens[1]) {
            (day, month) = (d, mo)
        }
        guard let day, let month else { return nil }

        if tokens.count == 3 {
            guard tokens[2].count == 4, let y = Int(tokens[2]) else { return nil }
            return LogicalDay(year: y, month: month, day: day)
        }
        let year = previous?.year ?? defaultYear
        guard let candidate = LogicalDay(year: year, month: month, day: day) else { return nil }
        if let previous, previous.days(to: candidate) < -180,
           let rolled = LogicalDay(year: year + 1, month: month, day: day) {
            return rolled
        }
        return candidate
    }
}
