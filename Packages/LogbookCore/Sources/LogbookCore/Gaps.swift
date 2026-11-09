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

/// Interval arithmetic for plan vs actual.
public enum Intervals {
    /// Merges overlapping intervals.
    public static func union(_ intervals: [DateInterval]) -> [DateInterval] {
        var out: [DateInterval] = []
        for i in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = out.last, i.start <= last.end {
                out[out.count - 1] = DateInterval(start: last.start, end: max(last.end, i.end))
            } else {
                out.append(i)
            }
        }
        return out
    }

    /// Total time covered by both sets (each set merged first, so nothing counts twice).
    public static func overlap(_ a: [DateInterval], _ b: [DateInterval]) -> TimeInterval {
        let ua = union(a), ub = union(b)
        var total: TimeInterval = 0
        for x in ua {
            for y in ub {
                if let i = x.intersection(with: y) { total += i.duration }
            }
        }
        return total
    }

    public static func total(_ intervals: [DateInterval]) -> TimeInterval {
        union(intervals).reduce(0) { $0 + $1.duration }
    }
}
