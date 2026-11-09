import Foundation

// MARK: Context

/// Everything detectors look at, as plain per-day series (oldest → newest; the
/// last day is today, which may be incomplete). `nil` means not logged.
public struct InsightContext: Sendable {
    public var today: LogicalDay
    public var now: Date
    public var timeZone: TimeZone
    public var days: [LogicalDay]
    /// Keys: work, sleep, kcal, protein, caffeine, nicotine, burn, steps, and
    /// `custom.<key>` for your own metrics.
    public var metrics: [String: [Double?]]
    /// Display names for custom metrics (`custom.weight` → "Weight (kg)").
    public var metricNames: [String: String]
    /// Last caffeine instant per day (nil = no caffeine logged that day).
    public var lastCaffeine: [Date?]
    /// Whether anything was logged that day (separates "no caffeine" from "not logged").
    public var anyLogged: [Bool]
    /// Sleep starts over the window (for the usual onset).
    public var sleepStarts: [Date]
    public var plan: PlanFacts

    public init(today: LogicalDay, now: Date, timeZone: TimeZone, days: [LogicalDay], metrics: [String: [Double?]],
                metricNames: [String: String] = [:],
                lastCaffeine: [Date?], anyLogged: [Bool], sleepStarts: [Date], plan: PlanFacts) {
        self.today = today
        self.now = now
        self.timeZone = timeZone
        self.days = days
        self.metrics = metrics
        self.metricNames = metricNames
        self.lastCaffeine = lastCaffeine
        self.anyLogged = anyLogged
        self.sleepStarts = sleepStarts
        self.plan = plan
    }

    public func series(_ key: String) -> [Double?] { metrics[key] ?? Array(repeating: nil, count: days.count) }

    /// Index of yesterday (the last complete day), if the window has it.
    public var yesterdayIndex: Int? { days.lastIndex(of: today.previous) }
}

/// Planning facts for the planning detectors.
public struct PlanFacts: Sendable {
    /// Minutes actual started after planned (negative = early), recent linked blocks.
    public var startDrifts: [Double]
    /// actual ÷ estimate for completed tasks with estimates, by list name.
    public var estimateRatios: [String: [Double]]
    /// Estimated minutes of open tasks scheduled for tomorrow.
    public var tomorrowTaskMinutes: Int
    /// Planned work minutes tomorrow.
    public var tomorrowPlannedWorkMinutes: Int

    public init(startDrifts: [Double] = [], estimateRatios: [String: [Double]] = [:], tomorrowTaskMinutes: Int = 0, tomorrowPlannedWorkMinutes: Int = 0) {
        self.startDrifts = startDrifts
        self.estimateRatios = estimateRatios
        self.tomorrowTaskMinutes = tomorrowTaskMinutes
        self.tomorrowPlannedWorkMinutes = tomorrowPlannedWorkMinutes
    }
}

// MARK: Candidates

public struct Insight: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case anomaly, trend, correlation, streak, habit, planning, dataQuality }
    public enum Confidence: String, Sendable, Comparable {
        case low, moderate, high
        var weight: Double { self == .high ? 1 : self == .moderate ? 0.7 : 0.4 }
        public static func < (a: Confidence, b: Confidence) -> Bool { a.weight < b.weight }
    }

    public var detectorID: String
    public var detectorVersion: Int
    /// De-duplication key: at most one card per subject (e.g. "sleep").
    public var subjectKey: String
    public var kind: Kind
    public var title: String
    /// "Why am I seeing this?": the data, the rule and its limits.
    public var explanation: [String]
    /// Standardised size of the effect (for ranking and the "grew by half" rule).
    public var effect: Double
    public var confidence: Confidence
    /// p-value for correlation-type insights (false-discovery control).
    public var pValue: Double?
    public var domain: String

    public init(detectorID: String, detectorVersion: Int, subjectKey: String, kind: Kind, title: String,
                explanation: [String], effect: Double, confidence: Confidence, pValue: Double?, domain: String) {
        self.detectorID = detectorID
        self.detectorVersion = detectorVersion
        self.subjectKey = subjectKey
        self.kind = kind
        self.title = title
        self.explanation = explanation
        self.effect = effect
        self.confidence = confidence
        self.pValue = pValue
        self.domain = domain
    }

    public var id: String { "\(detectorID):\(subjectKey)" }
    public var score: Double { effect * confidence.weight }
}

/// A detector: one file, one rule, its own minimum-data gate.
public protocol InsightDetector: Sendable {
    var id: String { get }
    var version: Int { get }
    func evaluate(_ context: InsightContext) -> [Insight]
}

/// What was shown before, so the same card doesn't nag.
public struct InsightMemoryState: Hashable, Sendable {
    public var detectorID: String
    public var subjectKey: String
    public var lastShownAt: Date?
    public var dismissedAt: Date?
    public var dismissedEffect: Double?
    public var snoozedUntil: Date?
    public var feedback: String?

    public init(detectorID: String, subjectKey: String, lastShownAt: Date? = nil, dismissedAt: Date? = nil,
                dismissedEffect: Double? = nil, snoozedUntil: Date? = nil, feedback: String? = nil) {
        self.detectorID = detectorID
        self.subjectKey = subjectKey
        self.lastShownAt = lastShownAt
        self.dismissedAt = dismissedAt
        self.dismissedEffect = dismissedEffect
        self.snoozedUntil = snoozedUntil
        self.feedback = feedback
    }
}

// MARK: Engine

public struct InsightEngine: Sendable {
    public var detectors: [any InsightDetector]
    /// Cards per day.
    public var limit: Int

    public init(detectors: [any InsightDetector] = InsightEngine.standardDetectors, limit: Int = 3) {
        self.detectors = detectors
        self.limit = limit
    }

    public static let standardDetectors: [any InsightDetector] = [
        BaselineDeviationDetector(), TrendDetector(), LateCaffeineDetector(), CaffeineSleepDetector(),
        SleepWorkDetector(), PersonalBestDetector(), PlanDriftDetector(), EstimateAccuracyDetector(),
        OvercommitDetector(), MissingBurnDetector(),
    ]

    /// Runs every detector, controls false discoveries across correlations
    /// (Benjamini–Hochberg at 10 %), drops what memory says to hold back, keeps
    /// one card per subject and the top `limit` by effect × confidence.
    public func run(_ context: InsightContext, memory: [InsightMemoryState]) -> [Insight] {
        var candidates = detectors.flatMap { $0.evaluate(context) }.filter { InsightText.isAllowed($0) }

        let tested = candidates.indices.filter { candidates[$0].pValue != nil }
        let keep = Stats.benjaminiHochberg(tested.map { candidates[$0].pValue! }, q: 0.1)
        let rejected = Set(zip(tested, keep).filter { !$0.1 }.map(\.0))
        candidates = candidates.enumerated().filter { !rejected.contains($0.offset) }.map(\.element)

        let byKey = Dictionary(memory.map { ("\($0.detectorID):\($0.subjectKey)", $0) }, uniquingKeysWith: { a, _ in a })
        candidates = candidates.filter { c in
            guard let m = byKey[c.id] else { return true }
            if let until = m.snoozedUntil, until > context.now { return false }
            if m.feedback == "wrong", let shown = m.lastShownAt, context.now.timeIntervalSince(shown) < 30 * 86_400 { return false }
            if let dismissed = m.dismissedAt, context.now.timeIntervalSince(dismissed) < 14 * 86_400 {
                // Back sooner only if the effect grew by half.
                return c.effect >= (m.dismissedEffect ?? .infinity) * 1.5
            }
            return true
        }

        var seen = Set<String>()
        return candidates
            .sorted { ($0.score, $0.id) > ($1.score, $1.id) }
            .filter { seen.insert($0.subjectKey).inserted }
            .prefix(limit)
            .map { $0 }
    }
}

/// Wording rules: patterns, not causes; no medical or moral language.
public enum InsightText {
    static let banned = ["cause", "causes", "caused", "because of", "should", "must", "risk", "diagnos", "disease",
                         "unhealthy", "bad", "good job", "failure", "failed"]

    public static func violations(_ text: String) -> [String] {
        let lower = text.lowercased()
        return banned.filter { word in
            if word.hasSuffix(" ") || word.contains(" ") || word == "diagnos" { return lower.contains(word) }
            return lower.split(whereSeparator: { !$0.isLetter }).contains { $0 == Substring(word) }
        }
    }

    public static func isAllowed(_ insight: Insight) -> Bool {
        violations(insight.title).isEmpty
    }
}
