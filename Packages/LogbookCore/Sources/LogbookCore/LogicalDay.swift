import Foundation

/// A day in the user's own sense (see `DayBoundary`), independent of time zone.
///
/// Stored in the database as `yyyy-MM-dd` text so that `GROUP BY logical_day`
/// and lexical ordering both work. Day arithmetic is pure proleptic-Gregorian
/// date arithmetic, so it is never affected by DST.
public struct LogicalDay: Hashable, Comparable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Creates a day, or returns `nil` if the date does not exist (e.g. 31 Feb).
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= Self.daysInMonth(year: year, month: month) else {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `yyyy-MM-dd`.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// `yyyy-MM-dd`, the database representation.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var rawValue: String { description }
    public init?(rawValue: String) { self.init(rawValue) }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let day = LogicalDay(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a yyyy-MM-dd day: \(text)"))
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public static func < (lhs: LogicalDay, rhs: LogicalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: Arithmetic

    /// Days since 1970-01-01 (can be negative). Uses the civil-from-days algorithm
    /// (H. Hinnant), so no `Calendar` or time zone is involved.
    public var daysSinceEpoch: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public init(daysSinceEpoch z0: Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        // Always valid by construction.
        self.year = y
        self.month = m
        self.day = d
    }

    public func adding(days: Int) -> LogicalDay {
        LogicalDay(daysSinceEpoch: daysSinceEpoch + days)
    }

    public var next: LogicalDay { adding(days: 1) }
    public var previous: LogicalDay { adding(days: -1) }

    /// Number of days from `self` to `other` (positive when `other` is later).
    public func days(to other: LogicalDay) -> Int {
        other.daysSinceEpoch - daysSinceEpoch
    }

    /// Every day from `start` through `end`, inclusive. Empty if `end < start`.
    public static func range(_ start: LogicalDay, through end: LogicalDay) -> [LogicalDay] {
        guard start <= end else { return [] }
        return (0...start.days(to: end)).map { start.adding(days: $0) }
    }

    static func isLeap(_ y: Int) -> Bool {
        (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}
