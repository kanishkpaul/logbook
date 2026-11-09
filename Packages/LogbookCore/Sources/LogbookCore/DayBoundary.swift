import Foundation

/// When a logical day starts, as a local wall-clock time.
///
/// `DayBoundary(hour: 0)` is the plain calendar day (master plan §3, option A).
/// `DayBoundary(hour: 5)` makes 01:00–03:30 work count toward the previous day
/// (option B). The boundary is applied when a row is written and the result is
/// stored, so changing this setting never rewrites history.
///
/// A logical day is the half-open interval `[start(of: d), start(of: d.next))`.
/// It is 23 or 25 hours long on DST transition days. When the start wall time
/// does not exist (a spring-forward gap), the day starts at the first instant
/// after the gap; when it occurs twice (fall-back), the first occurrence wins.
public struct DayBoundary: Hashable, Sendable, Codable {
    /// Minutes after local midnight, `0..<1440`.
    public let startMinutes: Int

    public init(hour: Int, minute: Int = 0) {
        precondition((0..<24).contains(hour) && (0..<60).contains(minute), "invalid day start \(hour):\(minute)")
        self.startMinutes = hour * 60 + minute
    }

    /// Option A: the calendar day.
    public static let calendarDay = DayBoundary(hour: 0)

    /// The boundary the app writes with (master plan §16, decision #1,
    /// 9 Nov 2026: calendar day). Changing it affects new rows only.
    public static let standard = calendarDay

    public var hour: Int { startMinutes / 60 }
    public var minute: Int { startMinutes % 60 }

    /// The instant at which `day` starts in `timeZone`.
    public func start(of day: LogicalDay, in timeZone: TimeZone) -> Date {
        let cal = Calendar.gregorian(in: timeZone)
        // Noon always exists; use it to find the civil day's first instant.
        let noon = cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
        let midnight = cal.startOfDay(for: noon)
        guard startMinutes > 0 else { return midnight }
        return cal.nextDate(
            after: midnight.addingTimeInterval(-1),
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )!
    }

    /// The half-open interval covered by `day` in `timeZone`.
    public func interval(of day: LogicalDay, in timeZone: TimeZone) -> DateInterval {
        DateInterval(start: start(of: day, in: timeZone), end: start(of: day.next, in: timeZone))
    }

    /// The logical day that contains `instant` in `timeZone`.
    public func logicalDay(containing instant: Date, in timeZone: TimeZone) -> LogicalDay {
        let civil = LogicalDay.civil(containing: instant, in: timeZone)
        return instant < start(of: civil, in: timeZone) ? civil.previous : civil
    }

    /// Splits `[start, end)` into the logical days it overlaps.
    ///
    /// Used for drawing timelines and for "minutes on day X" questions. This is
    /// *clipping*, which is different from *attribution* (which day a whole
    /// block's total counts toward). The segment durations always sum to
    /// `end − start`. Returns no segments when `end <= start`.
    public func clip(start: Date, end: Date, in timeZone: TimeZone) -> [DaySegment] {
        guard end > start else { return [] }
        var segments: [DaySegment] = []
        var day = logicalDay(containing: start, in: timeZone)
        var cursor = start
        while cursor < end {
            let dayEnd = self.start(of: day.next, in: timeZone)
            let segmentEnd = min(end, dayEnd)
            segments.append(DaySegment(day: day, interval: DateInterval(start: cursor, end: segmentEnd)))
            cursor = segmentEnd
            day = day.next
        }
        return segments
    }
}

/// One logical day's share of a longer interval.
public struct DaySegment: Hashable, Sendable {
    public let day: LogicalDay
    public let interval: DateInterval
}

extension LogicalDay {
    /// The calendar date of `instant` in `timeZone` (ignoring any day boundary).
    public static func civil(containing instant: Date, in timeZone: TimeZone) -> LogicalDay {
        let c = Calendar.gregorian(in: timeZone).dateComponents([.year, .month, .day], from: instant)
        return LogicalDay(year: c.year!, month: c.month!, day: c.day!)!
    }
}

extension Calendar {
    /// A Gregorian calendar fixed to `timeZone`, independent of the user's locale.
    public static func gregorian(in timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }
}
