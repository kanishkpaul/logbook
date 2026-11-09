import Foundation
import LogbookCore

/// One line of the source file, as written (trimmed of surrounding whitespace).
public struct SourceLine: Hashable, Sendable {
    public let number: Int
    public let text: String
}

/// A local wall-clock time on a given date. `minutes` is `0...1440`
/// (1440 = midnight at the end of `day`). Turned into an instant only when a
/// time zone is known (in the planner).
public struct WallTime: Hashable, Sendable, Comparable {
    public var day: LogicalDay
    public var minutes: Int

    public static func < (a: WallTime, b: WallTime) -> Bool {
        (a.day, a.minutes) < (b.day, b.minutes)
    }

    public func date(in timeZone: TimeZone) -> Date {
        let cal = Calendar.gregorian(in: timeZone)
        let d = minutes >= 1440 ? day.next : day
        let m = minutes % 1440
        return cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: m / 60, minute: m % 60))!
    }
}

public struct ParsedBlock: Hashable, Sendable {
    public var kind: BlockKind
    public var start: WallTime
    public var end: WallTime
    public var label: String
    /// The `[1h 18m]` the user typed, if any (a check, not the source of truth).
    public var typedMinutes: Int?
    public var isEstimate: Bool
}

public struct ParsedFood: Hashable, Sendable {
    /// The name as written, without the values part (e.g. `pulao 250g`).
    public var name: String
    /// The name without a trailing quantity, used for library matching (`pulao`).
    public var baseName: String
    public var quantity: Double?
    public var unit: String?
    /// Values typed on the line; `nil` when none were given.
    public var nutrition: Nutrition?
    /// Minutes after local midnight, if a `HH:MM` time prefixed the line.
    public var timeMinutes: Int?
    public var isEstimate: Bool

    /// Normalised key for library matching.
    public var matchKey: String { ParsedFood.matchKey(baseName) }

    public static func matchKey(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

public enum ParsedEntry: Hashable, Sendable {
    case block(ParsedBlock)
    case food(ParsedFood)
    case burn(kcal: Double, steps: Double?, isEstimate: Bool)
    case steps(Double, isEstimate: Bool)
    /// `$ 6h 30m`: the user's work total, used as a check.
    case workTotal(minutes: Int)
    /// `$ 1616 / 102 / 220`: an intake or net total, used as a check.
    case nutritionTotal(Nutrition)
}

public struct ParsedLine: Hashable, Sendable {
    public let line: SourceLine
    public let entry: ParsedEntry
}

public struct ParsedDay: Hashable, Sendable {
    public let date: LogicalDay
    public let header: SourceLine
    public var lines: [ParsedLine] = []
}

public struct ParsedDocument: Hashable, Sendable {
    public var days: [ParsedDay] = []
    public var issues: [ImportIssue] = []
    public var lineCount = 0
}

public struct ImportIssue: Hashable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable, Comparable {
        case error, warning, info
        public static func < (a: Severity, b: Severity) -> Bool {
            let order: [Severity] = [.error, .warning, .info]
            return order.firstIndex(of: a)! < order.firstIndex(of: b)!
        }
    }

    public enum Code: String, Sendable {
        /// A line before the first day header (skipped).
        case noDayYet
        /// A keyword line whose times can't be read (skipped).
        case unreadableTimes
        /// A `$` line that is neither a duration nor numbers.
        case unreadableTotal
        case typedDurationMismatch
        case workTotalMismatch
        case nutritionTotalMismatch
        /// A food with no values and no library match.
        case needsValues
        /// A food with no values, filled from the library and marked estimate.
        case valuesFromLibrary
        /// Same kind and times as an existing manually logged block (skipped).
        case likelyDuplicate
        /// Same day appears twice in the file (lines are merged into one day).
        case repeatedDay
    }

    public var severity: Severity
    public var code: Code
    public var line: Int?
    public var day: LogicalDay?
    public var message: String

    public var description: String {
        let place = [day?.description, line.map { "line \($0)" }].compactMap { $0 }.joined(separator: ", ")
        return "\(severity.rawValue): \(place.isEmpty ? "" : "[\(place)] ")\(message)"
    }
}
