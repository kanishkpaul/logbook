import Foundation

/// When you usually fall asleep, from your own logged sleep starts.
public enum SleepTiming {
    /// Median sleep onset as minutes from midnight, in `-720..<720`
    /// (negative = before midnight, e.g. -30 is 23:30; 75 is 01:15).
    /// `nil` until there are `minimum` starts.
    public static func usualOnset(_ starts: [Date], in timeZone: TimeZone, minimum: Int = 5) -> Int? {
        guard starts.count >= max(1, minimum) else { return nil }
        let cal = Calendar.gregorian(in: timeZone)
        let offsets = starts.map { d -> Int in
            let c = cal.dateComponents([.hour, .minute], from: d)
            let m = c.hour! * 60 + c.minute!
            return m >= 720 ? m - 1440 : m
        }.sorted()
        let mid = offsets.count / 2
        return offsets.count.isMultiple(of: 2) ? (offsets[mid - 1] + offsets[mid]) / 2 : offsets[mid]
    }

    /// The usual bedtime for the night that ends `day` (the coming night):
    /// the next midnight plus `onset` minutes.
    public static func bedtime(endingDay day: LogicalDay, onset: Int, in timeZone: TimeZone) -> Date {
        DayBoundary.calendarDay.start(of: day.next, in: timeZone).addingTimeInterval(Double(onset) * 60)
    }
}
