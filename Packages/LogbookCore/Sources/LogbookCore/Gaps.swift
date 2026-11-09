import Foundation

/// Unlogged stretches of a day, for the Close-the-day sheet.
public enum Gaps {
    /// Parts of `window` not covered by any of `covered`, at least `minimum` long.
    public static func unlogged(in window: DateInterval, covered: [DateInterval], minimum: TimeInterval = 30 * 60) -> [DateInterval] {
        let sorted = covered
            .compactMap { $0.intersection(with: window) }
            .sorted { $0.start < $1.start }
        var gaps: [DateInterval] = []
        var cursor = window.start
        for interval in sorted {
            if interval.start > cursor {
                gaps.append(DateInterval(start: cursor, end: interval.start))
            }
            cursor = max(cursor, interval.end)
        }
        if cursor < window.end { gaps.append(DateInterval(start: cursor, end: window.end)) }
        return gaps.filter { $0.duration >= minimum }
    }
}
