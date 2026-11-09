import Foundation
import LogbookCore
import LogbookPersistence

/// Turns a `DaySnapshot` into `TodayState`. Pure: same inputs, same output.
/// All maths comes from LogbookCore (durations, baselines, half-life model).
public struct TodayPresenter {
    public var timeZone: TimeZone
    public var caffeine: HalfLifeModel
    public var nicotine: HalfLifeModel

    public init(timeZone: TimeZone, caffeine: HalfLifeModel = .caffeine, nicotine: HalfLifeModel = .nicotine) {
        self.timeZone = timeZone
        self.caffeine = caffeine
        self.nicotine = nicotine
    }

    /// How long a timer may run before the guard asks "still going?".
    public static func forgottenAfter(_ kind: BlockKind) -> TimeInterval {
        switch kind {
        case .sleep: 14 * 3600
        case .natureCall: 2 * 3600
        default: 10 * 3600
        }
    }

    public func present(_ s: DaySnapshot, now: Date) -> TodayState {
        let timeFmt = Self.formatter("HH:mm", timeZone)
        let today = s.today
        let previous = s.previous
        let spanEnd = min(now, s.window.end)

        // Running work started today adds its elapsed time to today's total.
        let runningWorkMin = s.running
            .filter { $0.kind == .work && $0.logicalDay == s.day }
            .reduce(0) { total, b in total + Durations.minutes(from: b.startUTC, to: max(now, b.startUTC)) }
        let workMin = (today.workMin ?? 0) + runningWorkMin
        let hasWork = today.workMin != nil || runningWorkMin > 0

        let caffeineDoses = s.doses.compactMap { e in e.caffeineMg.flatMap { $0 > 0 ? Dose(at: e.consumedAt, mg: $0) : nil } }
        let nicotineDoses = s.doses.compactMap { e in e.nicotineMg.flatMap { $0 > 0 ? Dose(at: e.consumedAt, mg: $0) : nil } }
        let caffeineNow = caffeine.remaining(caffeineDoses, at: now)
        let nicotineNow = nicotine.remaining(nicotineDoses, at: now)
        // At your usual bedtime (median sleep onset of the last 28 nights).
        let onset = SleepTiming.usualOnset(s.sleepStarts, in: timeZone)
        let bedtime = onset.map { SleepTiming.bedtime(endingDay: s.day, onset: $0, in: timeZone) }
        func atBedtime(_ model: HalfLifeModel, _ doses: [Dose], _ fmt: (Double) -> String) -> String? {
            guard let bedtime, !doses.isEmpty else { return nil }
            return "≈ \(fmt(model.remaining(doses, at: bedtime))) mg at bedtime (\(timeFmt.string(from: bedtime)))"
        }
        let todaysCaffeine = caffeineDoses.filter { s.window.contains($0.at) }
        let lastCaffeine = todaysCaffeine.map(\.at).max()

        func spark(_ value: (DailyFacts) -> Double?) -> [TodayState.SparkPoint] {
            s.history.suffix(14).map { TodayState.SparkPoint(day: $0.logicalDay, value: value($0)) }
        }
        let duration = { (m: Double) in Durations.compact(minutes: Int(m.rounded())) }
        let number = { (v: Double) in NutritionFormat.number(v) }
        let whole = { (v: Double) in String(Int(v.rounded())) }

        var heroes: [TodayState.Hero] = []
        heroes.append(.init(
            id: "work", domain: .work, title: "Work today",
            value: hasWork ? Durations.compact(minutes: workMin) : "—", unit: "",
            headline: hasWork ? Headline.comparison(Double(workMin), to: Baseline(previous.map { $0.workMin.map(Double.init) }), format: duration) : nil,
            detail: runningWorkMin > 0 ? "includes the running timer" : nil,
            spark: spark { $0.workMin.map(Double.init) }
        ))
        let burn = today.burnKcal
        if let kcal = today.kcal, let burn {
            heroes.append(.init(
                id: "kcal", domain: .food, title: "Net kcal", value: whole(kcal - burn), unit: "kcal",
                headline: Headline.comparison(kcal, to: Baseline(previous.map(\.kcal)), format: { "\(whole($0)) kcal" })
                    .map { "intake \($0)" },
                detail: "\(whole(kcal)) in − \(whole(burn)) logged burn",
                spark: spark(\.kcal)
            ))
        } else {
            heroes.append(.init(
                id: "kcal", domain: .food, title: "kcal in", value: today.kcal.map(whole) ?? "—", unit: today.kcal == nil ? "" : "kcal",
                headline: today.kcal.flatMap { Headline.comparison($0, to: Baseline(previous.map(\.kcal)), format: { "\(whole($0)) kcal" }) },
                detail: today.kcal == nil ? nil : "burn not logged yet",
                spark: spark(\.kcal)
            ))
        }
        heroes.append(.init(
            id: "protein", domain: .food, title: "Protein", value: today.proteinG.map(number) ?? "—", unit: today.proteinG == nil ? "" : "g",
            headline: today.proteinG.flatMap { Headline.comparison($0, to: Baseline(previous.map(\.proteinG)), format: { "\(number($0)) g" }) },
            detail: nil, spark: spark(\.proteinG)
        ))
        heroes.append(.init(
            id: "caffeine", domain: .caffeine, title: "Caffeine now", value: whole(caffeineNow), unit: "mg",
            headline: atBedtime(caffeine, caffeineDoses, whole),
            detail: today.caffeineMg.map { "\(whole($0)) mg today" + (lastCaffeine.map { " · last \(timeFmt.string(from: $0))" } ?? "") + " · estimate" } ?? "estimate",
            spark: spark(\.caffeineMg)
        ))
        heroes.append(.init(
            id: "nicotine", domain: .nicotine, title: "Nicotine now", value: number(nicotineNow), unit: "mg",
            headline: atBedtime(nicotine, nicotineDoses, number), detail: today.nicotineMg.map { "\(number($0)) mg today · estimate" } ?? "estimate",
            spark: spark(\.nicotineMg)
        ))
        heroes.append(.init(
            id: "sleep", domain: .sleep, title: "Last night's sleep", value: today.sleepMin.map { Durations.compact(minutes: $0) } ?? "—", unit: "",
            headline: today.sleepMin.flatMap { Headline.comparison(Double($0), to: Baseline(previous.map { $0.sleepMin.map(Double.init) }), format: duration) },
            detail: nil, spark: spark { $0.sleepMin.map(Double.init) }
        ))

        // 24-hour track: blocks clipped to the day; running ones end at now.
        let track: [TodayState.TrackItem] = s.blocks.compactMap { b in
            let end = b.endUTC ?? max(now, b.startUTC)
            let start = max(b.startUTC, s.window.start), clippedEnd = min(end, s.window.end)
            guard clippedEnd > start else { return nil }
            let domain = Domain(kind: b.kind) ?? .work
            return .init(id: b.id, lane: domain.title, domain: domain, start: start, end: clippedEnd,
                         label: b.label, isRunning: b.endUTC == nil)
        }
        let marks = s.foods.map { TodayState.FoodMark(id: $0.id, at: $0.consumedAt, name: $0.name) }
        let curveEnd = spanEnd > s.window.start ? spanEnd : s.window.start
        let substances = caffeine.curve(caffeineDoses, from: s.window.start, to: curveEnd, step: 900)
            .map { TodayState.SubstancePoint(at: $0.0, substance: .caffeine, mg: $0.1) }
            + nicotine.curve(nicotineDoses, from: s.window.start, to: curveEnd, step: 900)
            .map { TodayState.SubstancePoint(at: $0.0, substance: .nicotine, mg: $0.1) }

        let running = s.running.map { b in
            TodayState.RunningTimer(
                id: b.id, kind: b.kind, domain: Domain(kind: b.kind) ?? .work,
                title: b.label.isEmpty ? (Domain(kind: b.kind)?.title ?? b.kind.rawValue) : b.label,
                start: b.startUTC, looksForgotten: now.timeIntervalSince(b.startUTC) > Self.forgottenAfter(b.kind)
            )
        }

        let blockRows = s.blocks.map { b in
            let end = b.endUTC ?? max(now, b.startUTC)
            let domain = Domain(kind: b.kind) ?? .work
            return TodayState.BlockRow(
                id: b.id, domain: domain, title: b.label.isEmpty ? domain.title : "\(domain.title) · \(b.label)",
                times: "\(timeFmt.string(from: b.startUTC))–\(b.endUTC.map { timeFmt.string(from: $0) } ?? "now")",
                duration: Durations.compact(minutes: Durations.minutes(from: b.startUTC, to: end)),
                isEstimate: b.isEstimate, isRunning: b.endUTC == nil
            )
        }
        let foodRows = s.foods.map { e in
            TodayState.FoodRow(id: e.id, time: timeFmt.string(from: e.consumedAt), name: e.name,
                               summary: NutritionFormat.compact(e.nutrition), needsValues: e.needsValues, isEstimate: e.isEstimate)
        }
        let sampleRows = s.samples.map { d in
            TodayState.SampleRow(id: d.id, title: d.name, value: "\(NutritionFormat.number(d.sample.value)) \(d.unit)".trimmingCharacters(in: .whitespaces))
        }
        // 7-day averages over logged days only (not-logged days are skipped, never zero).
        let week = previous.suffix(7).filter { $0.kcal != nil || $0.proteinG != nil }
        var weekAverage: String?
        if week.count >= 3 {
            func avg(_ k: KeyPath<DailyFacts, Double?>) -> Double? {
                let v = week.compactMap { $0[keyPath: k] }
                return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
            }
            let n = Nutrition(kcal: avg(\.kcal), proteinG: avg(\.proteinG), carbsG: avg(\.carbsG), fatG: avg(\.fatG))
            weekAverage = "7-day average · \(NutritionFormat.compact(n)) (\(week.count) days)"
        }
        let totals = NutritionFormat.parts(Nutrition(kcal: today.kcal, proteinG: today.proteinG, carbsG: today.carbsG,
                                                     fatG: today.fatG, caffeineMg: today.caffeineMg, nicotineMg: today.nicotineMg))

        // Close the day: unlogged gaps while awake, missing burn/steps, foods without values.
        let wake = s.blocks.filter { $0.kind == .sleep }.compactMap(\.endUTC).filter { s.window.contains($0) }.max()
        let awakeStart = wake ?? s.window.start
        var gaps: [CloseDayState.Gap] = []
        if spanEnd > awakeStart {
            let covered = s.blocks.map { DateInterval(start: $0.startUTC, end: max($0.endUTC ?? now, $0.startUTC)) }
            gaps = Gaps.unlogged(in: DateInterval(start: awakeStart, end: spanEnd), covered: covered, minimum: 45 * 60).map {
                .init(interval: $0, text: "\(timeFmt.string(from: $0.start))–\(timeFmt.string(from: $0.end)) · \(Durations.compact($0.duration))")
            }
        }
        var summary: [String] = []
        if hasWork { summary.append("Worked \(Durations.compact(minutes: workMin))") }
        if let sleep = today.sleepMin { summary.append("Slept \(Durations.compact(minutes: sleep))") }
        if !totals.isEmpty { summary.append(NutritionFormat.summary(Nutrition(kcal: today.kcal, proteinG: today.proteinG, carbsG: today.carbsG, fatG: today.fatG, caffeineMg: today.caffeineMg, nicotineMg: today.nicotineMg))) }
        let close = CloseDayState(
            gaps: gaps,
            missingBurn: !s.samples.contains { $0.key == "active_kcal" },
            missingSteps: !s.samples.contains { $0.key == "steps" },
            foodsNeedingValues: foodRows.filter(\.needsValues),
            summary: summary
        )

        var state = TodayState(
            day: s.day, title: Self.formatter("EEEE, d MMMM", timeZone).string(from: s.window.start.addingTimeInterval(12 * 3600)),
            window: s.window, now: now, heroes: heroes, track: track, foodMarks: marks, substances: substances,
            running: running, blocks: blockRows, foods: foodRows, samples: sampleRows, foodTotals: totals,
            weekAverage: weekAverage, closeDay: close
        )
        state.plan = presentPlan(s, now: now, timeFmt: timeFmt)
        state.closeDay.unfinishedTasks = state.plan.tasks.filter { !$0.isDone }
        state.closeDay.unreviewedPlans = state.plan.items.filter { $0.status == .planned && $0.isPast }
        return state
    }

    func presentPlan(_ s: DaySnapshot, now: Date, timeFmt: DateFormatter) -> PlanState {
        var plan = PlanState()
        let active = s.plans.filter { $0.status != .skipped }
        plan.items = s.plans.map { p in
            let domain = Domain(kind: p.kind) ?? .work
            return .init(id: p.id, domain: domain,
                         title: p.label.isEmpty ? domain.title : p.label,
                         times: "\(timeFmt.string(from: p.startUTC))–\(timeFmt.string(from: p.endUTC))",
                         duration: Durations.compact(minutes: p.minutes), status: p.status,
                         isNow: p.startUTC <= now && now < p.endUTC, isPast: p.endUTC <= now, start: p.startUTC)
        }
        plan.ghosts = active.compactMap { p in
            let start = max(p.startUTC, s.window.start), end = min(p.endUTC, s.window.end)
            guard end > start else { return nil }
            let domain = Domain(kind: p.kind) ?? .work
            return .init(id: p.id, lane: domain.title, domain: domain, start: start, end: end, label: p.label, isRunning: false)
        }
        plan.upNext = plan.items.first { $0.isNow && $0.status == .planned } ?? plan.items.first { !$0.isPast && !$0.isNow && $0.status == .planned }

        // Planned vs done: work only, up to now, overlap of time (no scoring, no colour).
        let planned = active.filter { $0.kind == .work }.compactMap { p -> DateInterval? in
            let end = min(p.endUTC, now)
            return end > p.startUTC ? DateInterval(start: p.startUTC, end: end) : nil
        }
        let totalPlanned = active.filter { $0.kind == .work }.reduce(0) { $0 + $1.minutes }
        if totalPlanned > 0 {
            let actual = s.blocks.filter { $0.kind == .work }.map { DateInterval(start: $0.startUTC, end: max($0.endUTC ?? now, $0.startUTC)) }
            let matched = Durations.minutes(Intervals.overlap(planned, actual))
            let soFar = Durations.minutes(Intervals.total(planned))
            var parts = ["Planned \(Durations.compact(minutes: totalPlanned)) of work"]
            if soFar > 0 {
                parts.append("\(Durations.compact(minutes: matched)) of the \(Durations.compact(minutes: soFar)) planned so far happened as planned")
            }
            let drifts = s.blocks.compactMap { b -> Double? in
                guard let pid = b.planBlockID, let p = s.plans.first(where: { $0.id == pid }) else { return nil }
                return b.startUTC.timeIntervalSince(p.startUTC) / 60
            }
            if !drifts.isEmpty {
                let median = Stats.quantile(drifts.sorted(), 0.5)
                if abs(median) >= 5 {
                    parts.append("started \(Durations.compact(minutes: Int(abs(median).rounded()))) \(median > 0 ? "later" : "earlier") than planned")
                }
            }
            plan.summary = parts.joined(separator: " · ")
        }

        func day(_ d: LogicalDay) -> String {
            if d == s.day { return "today" }
            if d == s.day.next { return "tomorrow" }
            if d == s.day.previous { return "yesterday" }
            return Self.formatter("EEE d MMM", timeZone).string(from: DayBoundary.calendarDay.start(of: d, in: timeZone).addingTimeInterval(43_200))
        }
        plan.tasks = s.tasks
            .sorted { a, b in
                let ka = (a.task.status == .open ? 0 : 1, -a.task.priority), kb = (b.task.status == .open ? 0 : 1, -b.task.priority)
                return ka < kb
            }
            .map { row in
                let t = row.task
                var parts: [String] = []
                if let e = t.estimateMin { parts.append("~\(Durations.compact(minutes: e))") }
                if row.actualMin > 0 { parts.append("\(Durations.compact(minutes: row.actualMin)) spent") }
                if let d = t.dueDay { parts.append("due \(day(d))") }
                if let sd = t.scheduledDay, sd < s.day { parts.append("from \(day(sd))") }
                if let l = row.listName { parts.append("#\(l)") }
                if let r = t.recurrence { parts.append(r.summary) }
                let overdue = t.status == .open && ((t.dueDay.map { $0 < s.day } ?? false) || (t.scheduledDay.map { $0 < s.day } ?? false))
                return .init(id: t.id, title: t.title, detail: parts.joined(separator: " · "), priority: t.priority,
                             isDone: t.status == .done, isOverdue: overdue)
            }
        return plan
    }

    static func formatter(_ format: String, _ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = tz
        f.dateFormat = format
        return f
    }
}
