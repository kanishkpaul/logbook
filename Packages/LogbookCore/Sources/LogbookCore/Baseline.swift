import Foundation

/// "Compare you with you": a metric's typical value over your recent days.
///
/// Built from per-day values where `nil` means *not logged* (skipped, never
/// counted as zero). Too few logged days → no baseline, so no comparison.
public struct Baseline: Hashable, Sendable {
    public let mean: Double
    public let median: Double
    /// Logged days that went into it.
    public let days: Int

    /// Fewest logged days before a comparison is shown.
    public static let minimumDays = 7

    public init?(_ values: [Double?], minimumDays: Int = Baseline.minimumDays) {
        let logged = values.compactMap { $0 }.sorted()
        guard logged.count >= max(1, minimumDays) else { return nil }
        mean = logged.reduce(0, +) / Double(logged.count)
        let mid = logged.count / 2
        median = logged.count.isMultiple(of: 2) ? (logged[mid - 1] + logged[mid]) / 2 : logged[mid]
        days = logged.count
    }
}

/// One-line, neutral wording for a value against its baseline:
/// "40m above your 4-week average", "about your 4-week average".
/// Never "good"/"bad", never colour; the UI decides nothing.
public enum Headline {
    /// - Parameters:
    ///   - tolerance: relative difference treated as "about the same" (default 10 %).
    ///   - format: how to print the absolute difference (e.g. `Durations.compact`).
    public static func comparison(
        _ value: Double,
        to baseline: Baseline?,
        tolerance: Double = 0.1,
        format: (Double) -> String
    ) -> String? {
        guard let baseline else { return nil }
        let diff = value - baseline.mean
        if baseline.mean == 0 ? diff == 0 : abs(diff) <= abs(baseline.mean) * tolerance {
            return "about your 4-week average"
        }
        return "\(format(abs(diff))) \(diff > 0 ? "above" : "below") your 4-week average"
    }
}
