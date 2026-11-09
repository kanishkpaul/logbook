import Foundation
import Testing
@testable import LogbookCore

/// Synthetic histories ending today (9 Nov 2026, 20:00 in Kolkata).
struct Scenario {
    static let tz = TimeZone(identifier: "Asia/Kolkata")!
    static let today = LogicalDay("2026-11-09")!
    let n: Int
    var metrics: [String: [Double?]] = [:]
    var lastCaffeine: [Date?]
    var anyLogged: [Bool]
    var sleepStarts: [Date] = []
    var plan = PlanFacts()
    var now: Date

    init(days n: Int = 60) {
        self.n = n
        lastCaffeine = Array(repeating: nil, count: n)
        anyLogged = Array(repeating: true, count: n)
        now = Scenario.at(Scenario.today, 20, 0)
    }

    var days: [LogicalDay] { (0..<n).map { Scenario.today.adding(days: $0 - n + 1) } }

    static func at(_ d: LogicalDay, _ h: Int, _ m: Int) -> Date {
        Calendar.gregorian(in: tz).date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: h, minute: m))!
    }

    /// value(i) for i in 0..<n (i = n−1 is today).
    mutating func set(_ key: String, _ value: (Int) -> Double?) {
        metrics[key] = (0..<n).map(value)
    }

    /// Falling asleep at 01:00 (± a little) every night.
    mutating func usualSleepAt1am(nights: Int = 30) {
        sleepStarts = (1...nights).map { k in Scenario.at(Scenario.today.adding(days: -k + 1), 1, (k % 3) * 5) }
    }

    var context: InsightContext {
        InsightContext(today: Scenario.today, now: now, timeZone: Scenario.tz, days: days, metrics: metrics,
                       lastCaffeine: lastCaffeine, anyLogged: anyLogged, sleepStarts: sleepStarts, plan: plan)
    }
}

@Suite struct InsightStatsTests {
    @Test func robust() {
        #expect(Stats.median([3, 1, 2]) == 2)
        #expect(Stats.mad([1, 2, 3, 4, 100]) == 1)
        #expect(Stats.robustZ(5, baseline: [5, 5, 5]) == nil, "no spread")
        let z = Stats.robustZ(10, baseline: [1, 2, 3, 4, 5])!
        #expect(abs(z - (10 - 3) / 1.4826) < 1e-9)
    }

    @Test func permutationIsDeterministicAndSensible() {
        let a = (0..<12).map { 100 + Double($0 % 3) }, b = (0..<12).map { 50 + Double($0 % 3) }
        let p = Stats.permutationPValue(a, b)
        #expect(p < 0.01)
        #expect(p == Stats.permutationPValue(a, b), "same seed, same answer")
        #expect(Stats.permutationPValue(a, a) > 0.5)
    }

    @Test func benjaminiHochberg() {
        // Classic example: with q = 0.1 the three smallest survive.
        #expect(Stats.benjaminiHochberg([0.01, 0.04, 0.03, 0.5, 0.9], q: 0.1) == [true, true, true, false, false])
        #expect(Stats.benjaminiHochberg([0.2, 0.3], q: 0.1) == [false, false])
    }
}

@Suite struct DetectorTests {
    func titles(_ d: any InsightDetector, _ s: Scenario) -> [String] { d.evaluate(s.context).map(\.title) }

    @Test func baselineDeviationFlagsAFarDayOnly() {
        var s = Scenario()
        s.set("work") { i in i == 58 ? 120 : 300 + Double((i % 5) * 10) - 20 }
        #expect(titles(BaselineDeviationDetector(), s) == ["Work yesterday was 3h below your usual (5h)"])
        s.set("work") { i in 300 + Double((i % 5) * 10) - 20 }
        #expect(titles(BaselineDeviationDetector(), s).isEmpty)
        var sparse = Scenario()
        sparse.set("work") { i in i == 58 ? 60 : (i % 4 == 0 ? 300 + Double(i % 3) * 10 : nil) }
        #expect(titles(BaselineDeviationDetector(), sparse).isEmpty, "fewer than 14 logged days")
    }

    @Test func trendNeedsSizeAndConsistency() {
        var s = Scenario()
        s.set("sleep") { i in (i >= 52 ? 480 : 420) + Double(i % 3) * 5 }
        #expect(titles(TrendDetector(), s) == ["Sleep over the past week: 1h more a day than the three weeks before"])
        s.set("sleep") { i in (i >= 52 ? 435 : 420) + Double(i % 3) * 5 }
        #expect(titles(TrendDetector(), s).isEmpty, "15 minutes is below the 30-minute bar")
    }

    @Test func lateCaffeineUsesYourOwnBedtime() {
        var s = Scenario()
        s.usualSleepAt1am()
        s.lastCaffeine[59] = Scenario.at(Scenario.today, 19, 40)
        #expect(titles(LateCaffeineDetector(), s) == ["Last caffeine at 19:40 is within 6h of your usual sleep time (01:05)"])
        s.lastCaffeine[59] = Scenario.at(Scenario.today, 18, 30)
        #expect(titles(LateCaffeineDetector(), s).isEmpty)
    }

    @Test func caffeineAndNextNightSleep() throws {
        var s = Scenario()
        s.usualSleepAt1am()
        for i in 0..<59 {
            let late = i % 2 == 0
            s.lastCaffeine[i] = Scenario.at(s.days[i], late ? 22 : 10, 0)
        }
        s.set("sleep") { i in i == 0 ? nil : ((i - 1) % 2 == 0 ? 360 : 450) + Double(i % 4) * 5 }
        let insight = try #require(CaffeineSleepDetector().evaluate(s.context).first)
        #expect(insight.title == "On days with caffeine after 19:05, you slept 1h 30m less the next night")
        #expect(insight.pValue! < 0.01 && insight.confidence == .high)
        #expect(insight.explanation.contains { $0.contains("not proof") })
    }

    @Test func sleepAndWork() {
        var s = Scenario()
        s.set("sleep") { i in i % 3 == 0 ? 320 : 450 }
        s.set("work") { i in i % 3 == 0 ? 200 : 330 }
        #expect(titles(SleepWorkDetector(), s) == ["On days after under 6h of sleep, you worked 2h 10m less (median)"])
    }

    @Test func personalBest() {
        var s = Scenario()
        s.set("work") { i in i == 58 ? 560 : 300 }
        #expect(titles(PersonalBestDetector(), s) == ["Yesterday was your longest work day in 6 weeks: 9h 20m"])
    }

    @Test func planningDetectors() {
        var s = Scenario()
        s.plan = PlanFacts(startDrifts: Array(repeating: 35, count: 12) + [5, 60],
                           estimateRatios: ["horizon": Array(repeating: 1.6, count: 9), "home": [1.0, 1.1]],
                           tomorrowTaskMinutes: 540, tomorrowPlannedWorkMinutes: 300)
        #expect(titles(PlanDriftDetector(), s) == ["You usually start planned blocks 35m later than planned"])
        #expect(titles(EstimateAccuracyDetector(), s) == ["Tasks in #horizon take 1.6× your estimate"])
        #expect(titles(OvercommitDetector(), s) == ["Tomorrow has 9h of tasks but 5h of planned work time"])
        s.plan.tomorrowPlannedWorkMinutes = 0
        #expect(titles(OvercommitDetector(), s).isEmpty, "no plan for tomorrow, nothing to compare")
    }

    @Test func missingBurn() {
        var s = Scenario()
        s.set("burn") { i in [53, 55, 57].contains(i) ? nil : 350 }
        #expect(titles(MissingBurnDetector(), s) == ["Burn missing on 3 of the last 7 logged days"])
    }
}

@Suite struct InsightEngineTests {
    func insight(_ id: String, subject: String, effect: Double, p: Double? = nil) -> Insight {
        Insight(detectorID: id, detectorVersion: 1, subjectKey: subject, kind: p == nil ? .anomaly : .correlation,
                title: "\(id) \(subject)", explanation: [], effect: effect, confidence: .high, pValue: p, domain: "work")
    }

    struct Fixed: InsightDetector {
        let id = "fixed"
        let version = 1
        let output: [Insight]
        func evaluate(_ context: InsightContext) -> [Insight] { output }
    }

    @Test func capsOnePerSubjectAndFalseDiscoveryControl() {
        let ctx = Scenario().context
        let engine = InsightEngine(detectors: [Fixed(output: [
            insight("a", subject: "work", effect: 3),
            insight("b", subject: "work", effect: 2),
            insight("c", subject: "sleep", effect: 1, p: 0.001),
            insight("d", subject: "kcal", effect: 5, p: 0.4),
            insight("e", subject: "steps", effect: 0.5),
            insight("f", subject: "protein", effect: 0.4),
        ])])
        let out = engine.run(ctx, memory: [])
        #expect(out.map(\.detectorID) == ["a", "c", "e"], "d fails FDR; b loses to a on the same subject; cap 3")
    }

    @Test func memoryHoldsBackDismissedAndSnoozed() {
        let ctx = Scenario().context
        let engine = InsightEngine(detectors: [Fixed(output: [
            insight("a", subject: "work", effect: 3),
            insight("b", subject: "sleep", effect: 2),
            insight("c", subject: "kcal", effect: 1),
        ])])
        let threeDaysAgo = ctx.now.addingTimeInterval(-3 * 86_400)
        let memory = [
            InsightMemoryState(detectorID: "a", subjectKey: "work", dismissedAt: threeDaysAgo, dismissedEffect: 2.5),
            InsightMemoryState(detectorID: "b", subjectKey: "sleep", dismissedAt: threeDaysAgo, dismissedEffect: 1),
            InsightMemoryState(detectorID: "c", subjectKey: "kcal", snoozedUntil: ctx.now.addingTimeInterval(3600)),
        ]
        #expect(engine.run(ctx, memory: memory).map(\.detectorID) == ["b"], "b's effect doubled since dismissal")
    }

    @Test func wordingRules() {
        #expect(InsightText.violations("Caffeine causes poor sleep") == ["causes"])
        #expect(InsightText.violations("You should sleep more").contains("should"))
        #expect(InsightText.violations("Bedtime has moved 50m later").isEmpty)
        #expect(InsightText.violations("Because of work").contains("because of"))
    }

    @Test func everyStandardDetectorTitleFollowsTheWordingRules() {
        var s = Scenario()
        s.usualSleepAt1am()
        s.set("work") { i in i == 58 ? 560 : (i % 3 == 0 ? 200 : 330) }
        s.set("sleep") { i in i % 3 == 0 ? 320 : 450 }
        s.set("burn") { i in i > 52 && i % 2 == 0 ? nil : 350 }
        s.lastCaffeine = (0..<60).map { i in Scenario.at(s.days[i], i % 2 == 0 ? 22 : 10, 0) }
        s.plan = PlanFacts(startDrifts: Array(repeating: 35, count: 12), estimateRatios: ["x": Array(repeating: 2, count: 8)],
                           tomorrowTaskMinutes: 600, tomorrowPlannedWorkMinutes: 120)
        let all = InsightEngine.standardDetectors.flatMap { $0.evaluate(s.context) }
        #expect(all.count >= 6)
        for i in all {
            #expect(InsightText.violations(i.title).isEmpty, "\(i.title)")
            #expect(!i.explanation.isEmpty)
        }
    }
}
