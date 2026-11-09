import Foundation
import LogbookCore
import LogbookPersistence

/// A week in review: this week against the one before, in plain sentences.
/// Template prose only (on-device AI phrasing comes in M9, from these facts).
public struct ReviewState: Equatable {
    public var title: String
    public var sections: [Section]
    public var loggedDays: Int
    /// Structured facts for the "In short" recap.
    public var facts: [RecapFact] = []

    public struct Section: Equatable, Identifiable {
        public var title: String
        public var domain: Domain
        public var lines: [String]
        public var id: String { title }
    }
}

public struct ReviewPresenter {
    public var timeZone: TimeZone

    public init(timeZone: TimeZone) {
        self.timeZone = timeZone
    }

    /// `range` must cover the previous week and this week (14 days, Monday first);
    /// `tasks` are rows with done/dropped tasks since the previous week began.
    public func present(_ range: RangeSnapshot, tasks: [TaskRow], weekStart: LogicalDay) -> ReviewState {
        let this = range.facts.filter { $0.logicalDay >= weekStart && $0.logicalDay <= weekStart.adding(days: 6) }
        let last = range.facts.filter { $0.logicalDay >= weekStart.adding(days: -7) && $0.logicalDay < weekStart }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = timeZone
        f.dateFormat = "d MMM"
        func noon(_ d: LogicalDay) -> Date { DayBoundary.calendarDay.start(of: d, in: timeZone).addingTimeInterval(43_200) }
        let title = "Week of \(f.string(from: noon(weekStart))) – \(f.string(from: noon(weekStart.adding(days: 6))))"
        let dayName = DateFormatter()
        dayName.locale = Locale(identifier: "en_GB")
        dayName.timeZone = timeZone
        dayName.dateFormat = "EEEE"

        func values(_ facts: [DailyFacts], _ k: (DailyFacts) -> Double?) -> [Double] { facts.compactMap(k) }
        func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        func change(_ a: Double?, _ b: Double?, _ fmt: (Double) -> String, more: String = "more", less: String = "less") -> String {
            guard let a, let b else { return "" }
            let d = a - b
            if abs(d) < max(abs(b) * 0.05, 1) { return ", about the same as the week before" }
            return ", \(fmt(abs(d))) \(d > 0 ? more : less) than the week before"
        }
        let dur = { (m: Double) in Durations.compact(minutes: Int(m.rounded())) }
        func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
        let whole = { (v: Double) in NutritionFormat.whole(v) }
        var sections: [ReviewState.Section] = []
        var facts: [RecapFact] = []

        // Work
        let work = values(this, { $0.workMin.map(Double.init) }), workLast = values(last, { $0.workMin.map(Double.init) })
        if !work.isEmpty {
            var lines = ["You worked \(dur(work.reduce(0, +))) (\(dur(avg(work)!)) a day on \(count(work.count, "logged day", "logged days")))\(change(avg(work), avg(workLast), { "\(dur($0)) a day" }))."]
            if let best = this.filter({ $0.workMin != nil }).max(by: { $0.workMin! < $1.workMin! }) {
                lines.append("Longest day: \(dayName.string(from: noon(best.logicalDay))), \(Durations.compact(minutes: best.workMin!)).")
            }
            let deep = range.blocks.filter { $0.kind == .work && $0.logicalDay >= weekStart && $0.logicalDay <= weekStart.adding(days: 6) }
                .filter { Durations.minutes(from: $0.startUTC, to: $0.endUTC ?? $0.startUTC) >= 50 }.count
            lines.append("\(deep) deep-work block\(deep == 1 ? "" : "s") of 50 minutes or more.")
            sections.append(.init(title: "Work", domain: .work, lines: lines))
            facts.append(RecapFact(id: "work", label: "work this week", value: dur(work.reduce(0, +)),
                                   comparison: change(avg(work), avg(workLast), { "\(dur($0)) a day" }).dropFirst(2).description.nilIfEmpty))
        }

        // Sleep
        let sleep = values(this, { $0.sleepMin.map(Double.init) }), sleepLast = values(last, { $0.sleepMin.map(Double.init) })
        if !sleep.isEmpty {
            var lines = ["You slept \(dur(avg(sleep)!)) a night on average (\(count(sleep.count, "night", "nights")))\(change(avg(sleep), avg(sleepLast), dur))."]
            let starts = range.blocks.filter { $0.kind == .sleep && $0.logicalDay >= weekStart && $0.logicalDay <= weekStart.adding(days: 6) }.map(\.startUTC)
            if let onset = SleepTiming.usualOnset(starts, in: timeZone, minimum: 3) {
                let cal = Calendar.gregorian(in: timeZone)
                let offsets = starts.map { d -> Double? in
                    let c = cal.dateComponents([.hour, .minute], from: d)
                    let m = Double(c.hour! * 60 + c.minute!)
                    return m >= 720 ? m - 1440 : m
                }
                let spread = Stats.standardDeviation(offsets) ?? 0
                lines.append("Usually asleep around \(HistoryPresenter.clock(Double(onset))); bedtime varied by ±\(dur(spread)).")
            }
            sections.append(.init(title: "Sleep", domain: .sleep, lines: lines))
            facts.append(RecapFact(id: "sleep", label: "average sleep a night", value: dur(avg(sleep)!),
                                   comparison: change(avg(sleep), avg(sleepLast), dur).dropFirst(2).description.nilIfEmpty))
        }

        // Food
        let kcal = values(this, \.kcal), kcalLast = values(last, \.kcal)
        if !kcal.isEmpty {
            let n = Nutrition(kcal: avg(kcal), proteinG: avg(values(this, \.proteinG)), carbsG: avg(values(this, \.carbsG)), fatG: avg(values(this, \.fatG)))
            var lines = ["A typical day: \(NutritionFormat.compact(n)) (\(count(kcal.count, "logged day", "logged days")))\(change(avg(kcal), avg(kcalLast), { "\(whole($0)) kcal" }))."]
            let caf = values(this, \.caffeineMg), nic = values(this, \.nicotineMg)
            if let c = avg(caf), c > 0 { lines.append("Caffeine: \(whole(c)) mg a day\(change(avg(caf), avg(values(last, \.caffeineMg)), { "\(whole($0)) mg" })).") }
            if !nic.isEmpty, nic.reduce(0, +) > 0 { lines.append("Nicotine: \(NutritionFormat.number(nic.reduce(0, +))) mg this week\(change(nic.reduce(0, +), values(last, \.nicotineMg).reduce(0, +), { "\(NutritionFormat.number($0)) mg" })).") }
            let missing = this.compactMap(\.foodNeedingValues).reduce(0, +)
            if missing > 0 { lines.append("\(count(missing, "food still needs", "foods still need")) values.") }
            sections.append(.init(title: "Food", domain: .food, lines: lines))
            facts.append(RecapFact(id: "kcal", label: "energy eaten on a typical day", value: "\(whole(avg(kcal)!)) kcal",
                                   comparison: change(avg(kcal), avg(kcalLast), { "\(whole($0)) kcal" }).dropFirst(2).description.nilIfEmpty))
        }

        // Body
        let steps = values(this, \.steps), burn = values(this, \.burnKcal)
        if !steps.isEmpty || !burn.isEmpty {
            var lines: [String] = []
            if let s = avg(steps) { lines.append("Steps: \(whole(s)) a day\(change(avg(steps), avg(values(last, \.steps)), whole))."); }
            if let b = avg(burn) { lines.append("Logged burn: \(whole(b)) kcal a day.") }
            sections.append(.init(title: "Body", domain: .energy, lines: lines))
        }

        // Plan
        let weekEnd = DayBoundary.calendarDay.start(of: weekStart.adding(days: 7), in: timeZone)
        let weekBegin = DayBoundary.calendarDay.start(of: weekStart, in: timeZone)
        let done = tasks.filter { $0.task.status == .done && ($0.task.completedAt.map { $0 >= weekBegin && $0 < weekEnd } ?? false) }
        let dropped = tasks.filter { $0.task.status == .dropped && ($0.task.completedAt.map { $0 >= weekBegin && $0 < weekEnd } ?? false) }
        let plans = range.plans.filter { $0.logicalDay >= weekStart && $0.logicalDay <= weekStart.adding(days: 6) && $0.status != .skipped && $0.kind == .work }
        if !done.isEmpty || !plans.isEmpty {
            var lines: [String] = []
            if !done.isEmpty {
                lines.append("\(done.count) task\(done.count == 1 ? "" : "s") done\(dropped.isEmpty ? "" : ", \(dropped.count) dropped").")
                facts.append(RecapFact(id: "tasks", label: "tasks done this week", value: "\(done.count)"))
            }
            if !plans.isEmpty {
                let planned = plans.map { DateInterval(start: $0.startUTC, end: $0.endUTC) }
                let actual = range.blocks.filter { $0.kind == .work }.compactMap { b in b.endUTC.map { DateInterval(start: b.startUTC, end: $0) } }
                let total = Durations.minutes(Intervals.total(planned)), matched = Durations.minutes(Intervals.overlap(planned, actual))
                lines.append("Planned \(Durations.compact(minutes: total)) of work; \(Durations.compact(minutes: matched)) of it happened as planned.")
            }
            sections.append(.init(title: "Plan", domain: .work, lines: lines))
        }

        let logged = this.filter { !$0.isEmpty }.count
        return ReviewState(title: title, sections: sections, loggedDays: logged, facts: facts)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
