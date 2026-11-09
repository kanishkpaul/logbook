import Foundation

// Each detector: one rule, a minimum-data gate, neutral wording, and an
// explanation of what it looked at. Thresholds are tunable defaults.

enum Fmt {
    static func duration(_ m: Double) -> String { Durations.compact(minutes: Int(m.rounded())) }
    static func value(_ key: String, _ v: Double) -> String {
        switch key {
        case "work", "sleep": duration(v)
        case "kcal": "\(Int(v.rounded())) kcal"
        case "protein": "\(Int(v.rounded())) g"
        case "steps": "\(Int(v.rounded())) steps"
        default: NutritionFormat.number(v)
        }
    }
    static func name(_ key: String) -> String {
        ["work": "Work", "sleep": "Sleep", "kcal": "kcal in", "protein": "Protein", "steps": "Steps"][key] ?? key
    }
    static func clock(_ date: Date, _ tz: TimeZone) -> String {
        let c = Calendar.gregorian(in: tz).dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }
    static func confidence(days: Int) -> Insight.Confidence {
        days >= 28 ? .high : days >= 20 ? .moderate : .low
    }
}

/// "Work yesterday was 2h 10m below your usual": robust z against your last 28 days.
public struct BaselineDeviationDetector: InsightDetector {
    public let id = "baseline"
    public let version = 1
    let metrics = ["work", "sleep", "kcal", "protein", "steps"]
    public init() {}

    public func evaluate(_ c: InsightContext) -> [Insight] {
        guard let y = c.yesterdayIndex, y >= 3 else { return [] }
        return metrics.compactMap { key in
            let s = c.series(key)
            guard let x = s[y] else { return nil }
            let baseline = s[max(0, y - 30)..<(y - 2)].compactMap { $0 }.suffix(28)
            guard baseline.count >= 14, let z = Stats.robustZ(x, baseline: Array(baseline)),
                  let median = Stats.median(Array(baseline)) else { return nil }
            let recent = [s[y - 1], s[y - 2]].compactMap { $0 }.compactMap { Stats.robustZ($0, baseline: Array(baseline)) }
            let repeated = abs(z) >= 2 && recent.contains { abs($0) >= 2 && ($0 > 0) == (z > 0) }
            guard abs(z) >= 3 || repeated else { return nil }
            let range = Stats.typicalRange(Array(baseline).map { Optional($0) })
            return Insight(
                detectorID: id, detectorVersion: version, subjectKey: key, kind: .anomaly,
                title: "\(Fmt.name(key)) yesterday was \(Fmt.value(key, abs(x - median))) \(x > median ? "above" : "below") your usual (\(Fmt.value(key, median)))",
                explanation: [
                    "Compared with your last \(baseline.count) logged days\(range.map { ", where the middle half ran \(Fmt.value(key, $0.low))–\(Fmt.value(key, $0.high))" } ?? "").",
                    repeated ? "Shown because it is the second unusual day in the last three (robust z \(String(format: "%.1f", z)))."
                        : "Shown because it is far from your own pattern (robust z \(String(format: "%.1f", z)); the bar is 3).",
                    "Days with nothing logged are skipped, not counted as zero.",
                ],
                effect: abs(z), confidence: Fmt.confidence(days: baseline.count), pValue: nil, domain: key
            )
        }
    }
}

/// "Sleep over the past week: 50m more than the three weeks before."
public struct TrendDetector: InsightDetector {
    public let id = "trend"
    public let version = 1
    public init() {}

    public func evaluate(_ c: InsightContext) -> [Insight] {
        guard let y = c.yesterdayIndex else { return [] }
        var out: [Insight] = []
        for (key, threshold) in [("work", 45.0), ("sleep", 30.0)] {
            let s = c.series(key)
            let recent = s[max(0, y - 6)...y].compactMap { $0 }
            let before = s[max(0, y - 27)..<max(0, y - 6)].compactMap { $0 }
            if let t = trend(key: key, recent: recent, before: before, threshold: threshold, name: Fmt.name(key)) { out.append(t) }
        }
        // Bedtime: onsets as minutes from midnight (−720…720).
        let cal = Calendar.gregorian(in: c.timeZone)
        func offset(_ d: Date) -> Double {
            let comp = cal.dateComponents([.hour, .minute], from: d)
            let m = Double(comp.hour! * 60 + comp.minute!)
            return m >= 720 ? m - 1440 : m
        }
        let weekAgo = c.now.addingTimeInterval(-7 * 86_400), monthAgo = c.now.addingTimeInterval(-28 * 86_400)
        let recent = c.sleepStarts.filter { $0 >= weekAgo }.map(offset)
        let before = c.sleepStarts.filter { $0 >= monthAgo && $0 < weekAgo }.map(offset)
        if let t = trend(key: "bedtime", recent: recent, before: before, threshold: 30, name: "Bedtime") { out.append(t) }
        return out
    }

    func trend(key: String, recent: [Double], before: [Double], threshold: Double, name: String) -> Insight? {
        guard recent.count >= 5, before.count >= 14 else { return nil }
        let a = recent.reduce(0, +) / Double(recent.count), b = before.reduce(0, +) / Double(before.count)
        let diff = a - b
        let sd = Stats.standardDeviation(before.map { Optional($0) }) ?? 0
        guard abs(diff) >= threshold, abs(diff) >= 0.5 * sd else { return nil }
        let title = key == "bedtime"
            ? "Bedtime has moved \(Fmt.duration(abs(diff))) \(diff > 0 ? "later" : "earlier") over the past week"
            : "\(name) over the past week: \(Fmt.duration(abs(diff))) \(diff > 0 ? "more" : "less") a day than the three weeks before"
        return Insight(
            detectorID: id, detectorVersion: version, subjectKey: key == "bedtime" ? "bedtime" : key, kind: .trend, title: title,
            explanation: [
                "Average of the last 7 days (\(recent.count) logged) against the 21 days before (\(before.count) logged).",
                "Shown because the change is at least \(Fmt.duration(threshold)) and larger than your usual day-to-day spread.",
            ],
            effect: abs(diff) / max(sd, 1), confidence: recent.count >= 7 ? .moderate : .low, pValue: nil, domain: key == "bedtime" ? "sleep" : key
        )
    }
}

/// "Last caffeine at 23:40 is within 6h of your usual sleep time (01:15)."
public struct LateCaffeineDetector: InsightDetector {
    public let id = "late-caffeine"
    public let version = 1
    public init() {}

    public func evaluate(_ c: InsightContext) -> [Insight] {
        guard let onset = SleepTiming.usualOnset(c.sleepStarts, in: c.timeZone, minimum: 14),
              let last = c.lastCaffeine.last ?? nil, last <= c.now else { return [] }
        let bedtime = SleepTiming.bedtime(endingDay: c.today, onset: onset, in: c.timeZone)
        let cutoff = bedtime.addingTimeInterval(-6 * 3600)
        guard last > cutoff else { return [] }
        return [Insight(
            detectorID: id, detectorVersion: version, subjectKey: "caffeine-timing", kind: .habit,
            title: "Last caffeine at \(Fmt.clock(last, c.timeZone)) is within 6h of your usual sleep time (\(Fmt.clock(bedtime, c.timeZone)))",
            explanation: [
                "Your usual sleep time is the median of your last \(c.sleepStarts.count) logged sleep starts.",
                "The 6-hour window comes from a sleep-lab study (Drake et al., 2013); your own data may differ.",
            ],
            effect: 1.5, confidence: .moderate, pValue: nil, domain: "caffeine"
        )]
    }
}

/// Two groups of days compared by median, with a permutation test.
struct GroupComparison {
    let a: [Double]
    let b: [Double]
    var diff: Double { (Stats.median(a) ?? 0) - (Stats.median(b) ?? 0) }
    var p: Double { Stats.permutationPValue(a, b) }

    func confidence(_ p: Double) -> Insight.Confidence {
        p < 0.01 && a.count + b.count >= 30 ? .high : p < 0.05 ? .moderate : .low
    }
}

/// "On days with caffeine after 19:15, you slept 48m less the next night."
public struct CaffeineSleepDetector: InsightDetector {
    public let id = "caffeine-sleep"
    public let version = 1
    public init() {}

    public func evaluate(_ c: InsightContext) -> [Insight] {
        guard let onset = SleepTiming.usualOnset(c.sleepStarts, in: c.timeZone, minimum: 14) else { return [] }
        let sleep = c.series("sleep")
        var late: [Double] = [], early: [Double] = []
        for i in 0..<(c.days.count - 1) where c.anyLogged[i] {
            guard let next = sleep[i + 1] else { continue }
            let cutoff = SleepTiming.bedtime(endingDay: c.days[i], onset: onset, in: c.timeZone).addingTimeInterval(-6 * 3600)
            if let last = c.lastCaffeine[i], last > cutoff { late.append(next) } else { early.append(next) }
        }
        guard late.count >= 8, early.count >= 8 else { return [] }
        let g = GroupComparison(a: late, b: early)
        guard abs(g.diff) >= 15 else { return [] }
        let p = g.p
        let cutoffClock = Fmt.clock(SleepTiming.bedtime(endingDay: c.today, onset: onset, in: c.timeZone).addingTimeInterval(-6 * 3600), c.timeZone)
        return [Insight(
            detectorID: id, detectorVersion: version, subjectKey: "sleep", kind: .correlation,
            title: "On days with caffeine after \(cutoffClock), you slept \(Fmt.duration(abs(g.diff))) \(g.diff < 0 ? "less" : "more") the next night",
            explanation: [
                "Median sleep after \(late.count) days with late caffeine vs \(early.count) days without.",
                "Late = after your usual sleep time minus 6 hours. Chance of a gap this size by luck: about \(String(format: "%.0f", p * 100))%.",
                "A pattern in your log, not proof that caffeine is the reason. Try two weeks with an earlier cutoff to see.",
            ],
            effect: abs(g.diff) / max(Stats.standardDeviation((late + early).map { Optional($0) }) ?? 1, 1),
            confidence: g.confidence(p), pValue: p, domain: "sleep"
        )]
    }
}

/// "On days after under 6h of sleep, you worked 1h 40m less."
public struct SleepWorkDetector: InsightDetector {
    public let id = "sleep-work"
    public let version = 1
    public init() {}

    public func evaluate(_ c: InsightContext) -> [Insight] {
        let sleep = c.series("sleep"), work = c.series("work")
        var short: [Double] = [], normal: [Double] = []
        for i in 0..<max(0, c.days.count - 1) {
            guard let s = sleep[i], let w = work[i] else { continue }
            if s < 360 { short.append(w) } else { normal.append(w) }
        }
        guard short.count >= 8, normal.count >= 8 else { return [] }
        let g = GroupComparison(a: short, b: normal)
        guard abs(g.diff) >= 30 else { return [] }
        let p = g.p
        return [Insight(
            detectorID: id, detectorVersion: version, subjectKey: "work", kind: .correlation,
            title: "On days after under 6h of sleep, you worked \(Fmt.duration(abs(g.diff))) \(g.diff < 0 ? "less" : "more") (median)",
            explanation: [
                "Median work on \(short.count) days after short sleep vs \(normal.count) days after 6h or more.",
                "Chance of a gap this size by luck: about \(String(format: "%.0f", p * 100))%. A pattern, not a reason.",
            ],
            effect: abs(g.diff) / max(Stats.standardDeviation((short + normal).map { Optional($0) }) ?? 1, 1),
            confidence: g.confidence(p), pValue: p, domain: "work"
        )]
    }
}

/// "Longest work day in 6 weeks: 9h 10m."
public struct PersonalBestDetector: InsightDetector {
    public let id = "best"
    public let version = 1
    public init() {}

    public func evaluate(_ c: InsightContext) -> [Insight] {
        guard let y = c.yesterdayIndex, let x = c.series("work")[y] else { return [] }
        let before = c.series("work")[max(0, y - 41)..<y].compactMap { $0 }
        guard before.count >= 28, x > (before.max() ?? .infinity) else { return [] }
        return [Insight(
            detectorID: id, detectorVersion: version, subjectKey: "work-best", kind: .streak,
            title: "Yesterday was your longest work day in 6 weeks: \(Fmt.duration(x))",
            explanation: ["Compared with your \(before.count) logged days in the previous 6 weeks."],
            effect: 1.2, confidence: .high, pValue: nil, domain: "work"
        )]
    }
}

/// "You usually start planned blocks 35m late."
public struct PlanDriftDetector: InsightDetector {
    public let id = "plan-drift"
    public let version = 1
    public init() {}

    public func evaluate(_ c: InsightContext) -> [Insight] {
        let drifts = c.plan.startDrifts
        guard drifts.count >= 10, let m = Stats.median(drifts), abs(m) >= 10 else { return [] }
        return [Insight(
            detectorID: id, detectorVersion: version, subjectKey: "plan-start", kind: .planning,
            title: "You usually start planned blocks \(Fmt.duration(abs(m))) \(m > 0 ? "later" : "earlier") than planned",
            explanation: [
                "Median over your last \(drifts.count) planned blocks that you started from the plan.",
                "Useful for planning: blocks could start that much \(m > 0 ? "later" : "earlier"), or a reminder could come sooner.",
            ],
            effect: abs(m) / 30, confidence: drifts.count >= 20 ? .high : .moderate, pValue: nil, domain: "work"
        )]
    }
}

/// "Tasks in #horizon take 1.6× your estimate."
public struct EstimateAccuracyDetector: InsightDetector {
    public let id = "estimates"
    public let version = 1
    public init() {}

    public func evaluate(_ c: InsightContext) -> [Insight] {
        c.plan.estimateRatios.sorted { $0.key < $1.key }.compactMap { list, ratios in
            guard ratios.count >= 8, let m = Stats.median(ratios), m >= 1.3 || m <= 0.7 else { return nil }
            return Insight(
                detectorID: id, detectorVersion: version, subjectKey: "estimates-\(list.lowercased())", kind: .planning,
                title: "Tasks in #\(list) take \(String(format: "%.1f", m))× your estimate",
                explanation: ["Median of time spent ÷ estimate over \(ratios.count) finished tasks in #\(list) with an estimate."],
                effect: abs(log(m)) * 2, confidence: ratios.count >= 15 ? .high : .moderate, pValue: nil, domain: "work"
            )
        }
    }
}

/// "Tomorrow has 9h of tasks but 5h of planned work time."
public struct OvercommitDetector: InsightDetector {
    public let id = "overcommit"
    public let version = 1
    public init() {}

    public func evaluate(_ c: InsightContext) -> [Insight] {
        let tasks = c.plan.tomorrowTaskMinutes, planned = c.plan.tomorrowPlannedWorkMinutes
        guard planned > 0, tasks - planned >= 60 else { return [] }
        return [Insight(
            detectorID: id, detectorVersion: version, subjectKey: "tomorrow", kind: .planning,
            title: "Tomorrow has \(Fmt.duration(Double(tasks))) of tasks but \(Fmt.duration(Double(planned))) of planned work time",
            explanation: ["Sum of estimates for open tasks scheduled tomorrow vs work blocks planned for tomorrow."],
            effect: Double(tasks - planned) / 120, confidence: .high, pValue: nil, domain: "work"
        )]
    }
}

/// "Burn missing on 3 of the last 7 logged days."
public struct MissingBurnDetector: InsightDetector {
    public let id = "missing-burn"
    public let version = 1
    public init() {}

    public func evaluate(_ c: InsightContext) -> [Insight] {
        guard let y = c.yesterdayIndex else { return [] }
        let burn = c.series("burn")
        let days = (max(0, y - 6)...y).filter { c.anyLogged[$0] }
        let missing = days.filter { burn[$0] == nil }.count
        guard days.count >= 5, missing >= 3 else { return [] }
        return [Insight(
            detectorID: id, detectorVersion: version, subjectKey: "burn-logging", kind: .dataQuality,
            title: "Burn missing on \(missing) of the last \(days.count) logged days",
            explanation: ["Net kcal and energy trends need burn; days without it are left out, not counted as zero."],
            effect: 0.8, confidence: .high, pValue: nil, domain: "energy"
        )]
    }
}
