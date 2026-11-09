import Foundation

/// A dose of a substance taken at an instant (caffeine or nicotine, in mg).
public struct Dose: Hashable, Sendable {
    public var at: Date
    public var mg: Double

    public init(at: Date, mg: Double) {
        self.at = at
        self.mg = mg
    }
}

/// Single-compartment exponential elimination: each dose decays by half every
/// `halfLife`. It is a model estimate, labelled as such in the UI; the
/// half-lives are user-adjustable defaults, not medical facts.
public struct HalfLifeModel: Hashable, Sendable {
    public var halfLife: TimeInterval

    public init(halfLife: TimeInterval) {
        precondition(halfLife > 0)
        self.halfLife = halfLife
    }

    /// Caffeine: 5 h default (dedicated apps let users pick 2–10 h).
    public static let caffeine = HalfLifeModel(halfLife: 5 * 3600)
    /// Nicotine: 2 h default.
    public static let nicotine = HalfLifeModel(halfLife: 2 * 3600)

    /// mg still in the system at `time`. Doses after `time` don't count.
    public func remaining(_ doses: [Dose], at time: Date) -> Double {
        doses.reduce(0) { sum, d in
            let elapsed = time.timeIntervalSince(d.at)
            guard elapsed >= 0 else { return sum }
            return sum + d.mg * pow(0.5, elapsed / halfLife)
        }
    }

    /// The curve between two instants, one point per `step`, for charts.
    public func curve(_ doses: [Dose], from start: Date, to end: Date, step: TimeInterval = 600) -> [(Date, Double)] {
        guard end > start, step > 0 else { return [] }
        var points: [(Date, Double)] = []
        var t = start
        while t <= end {
            points.append((t, remaining(doses, at: t)))
            t = t.addingTimeInterval(step)
        }
        return points
    }
}
