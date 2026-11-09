import Foundation

/// Small, honest statistics for personal logs. Inputs are per-day values in
/// which `nil` means *not logged*: skipped, never treated as zero.
public enum Stats {
    /// Trailing mean over `window` days, using only logged days, and only once
    /// at least `minimum` of them are logged; otherwise `nil` for that day.
    public static func rollingMean(_ values: [Double?], window: Int = 7, minimum: Int = 3) -> [Double?] {
        values.indices.map { i in
            let slice = values[max(0, i - window + 1)...i].compactMap { $0 }
            guard slice.count >= minimum else { return nil }
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    /// The `p` quantile (0…1) of sorted values, linearly interpolated.
    public static func quantile(_ sorted: [Double], _ p: Double) -> Double {
        precondition(!sorted.isEmpty)
        let pos = p * Double(sorted.count - 1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }

    /// Your typical range: the middle half (25th–75th percentile) and median
    /// of logged values; `nil` with fewer than `minimum` logged days.
    public struct TypicalRange: Hashable, Sendable {
        public let low: Double
        public let median: Double
        public let high: Double
        public let days: Int
    }

    public static func typicalRange(_ values: [Double?], minimum: Int = 7) -> TypicalRange? {
        let v = values.compactMap { $0 }.sorted()
        guard v.count >= max(1, minimum) else { return nil }
        return TypicalRange(low: quantile(v, 0.25), median: quantile(v, 0.5), high: quantile(v, 0.75), days: v.count)
    }

    /// Population standard deviation of logged values (`nil` if fewer than 2).
    public static func standardDeviation(_ values: [Double?]) -> Double? {
        let v = values.compactMap { $0 }
        guard v.count >= 2 else { return nil }
        let mean = v.reduce(0, +) / Double(v.count)
        return (v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(v.count)).squareRoot()
    }

    /// Pearson correlation over days where both values are logged.
    public struct Correlation: Hashable, Sendable {
        public let r: Double
        public let n: Int

        /// Plain-language strength, never causal.
        public var strength: String {
            switch abs(r) {
            case ..<0.1: "no clear relationship"
            case ..<0.3: "a weak relationship"
            case ..<0.5: "a moderate relationship"
            default: "a strong relationship"
            }
        }

        /// How much to trust it, from the number of paired days only.
        public var confidence: String {
            switch n {
            case ..<15: "low confidence"
            case ..<40: "moderate confidence"
            default: "higher confidence"
            }
        }

        public var direction: String { r >= 0 ? "higher" : "lower" }
    }

    /// `nil` with fewer than `minimum` paired days or no variation.
    public static func correlation(_ x: [Double?], _ y: [Double?], minimum: Int = 8) -> Correlation? {
        let pairs = zip(x, y).compactMap { a, b -> (Double, Double)? in
            guard let a, let b else { return nil }
            return (a, b)
        }
        guard pairs.count >= minimum else { return nil }
        let n = Double(pairs.count)
        let mx = pairs.map(\.0).reduce(0, +) / n, my = pairs.map(\.1).reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (a, b) in pairs {
            sxy += (a - mx) * (b - my)
            sxx += (a - mx) * (a - mx)
            syy += (b - my) * (b - my)
        }
        guard sxx > 0, syy > 0 else { return nil }
        return Correlation(r: sxy / (sxx * syy).squareRoot(), n: pairs.count)
    }

    /// Least-squares line `y = a + b·x` over paired logged days, for a trend line.
    public static func linearFit(_ x: [Double?], _ y: [Double?]) -> (intercept: Double, slope: Double)? {
        let pairs = zip(x, y).compactMap { a, b -> (Double, Double)? in
            guard let a, let b else { return nil }
            return (a, b)
        }
        guard pairs.count >= 2 else { return nil }
        let n = Double(pairs.count)
        let mx = pairs.map(\.0).reduce(0, +) / n, my = pairs.map(\.1).reduce(0, +) / n
        let sxx = pairs.map { ($0.0 - mx) * ($0.0 - mx) }.reduce(0, +)
        guard sxx > 0 else { return nil }
        let slope = pairs.map { ($0.0 - mx) * ($0.1 - my) }.reduce(0, +) / sxx
        return (my - slope * mx, slope)
    }
}

/// A block's share of each calendar day, as minutes from that day's start —
/// for week and month grids. Uses clipping (not attribution), so an overnight
/// sleep appears on both days.
public struct DayPart: Hashable, Sendable {
    public var day: LogicalDay
    /// Minutes from the day's start, `0...1440` (23/25-hour days are scaled to fit).
    public var startMinute: Double
    public var endMinute: Double

    public static func parts(start: Date, end: Date, in timeZone: TimeZone, boundary: DayBoundary = .standard) -> [DayPart] {
        boundary.clip(start: start, end: end, in: timeZone).map { seg in
            let window = boundary.interval(of: seg.day, in: timeZone)
            let scale = 1440 / (window.duration / 60)
            return DayPart(
                day: seg.day,
                startMinute: seg.interval.start.timeIntervalSince(window.start) / 60 * scale,
                endMinute: seg.interval.end.timeIntervalSince(window.start) / 60 * scale
            )
        }
    }
}
