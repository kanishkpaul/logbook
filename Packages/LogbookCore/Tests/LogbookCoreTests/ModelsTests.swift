import Foundation
import Testing
@testable import LogbookCore

@Suite struct NutritionMathTests {
    @Test func sumsKnownFieldsAndKeepsUnknownAsNil() {
        let a = Nutrition(kcal: 408, proteinG: 8, caffeineMg: 0)
        let b = Nutrition(kcal: 40, proteinG: 1, fatG: 2, caffeineMg: 110)
        let s = a + b
        #expect(s.kcal == 448 && s.proteinG == 9 && s.caffeineMg == 110)
        #expect(s.fatG == 2, "unknown on one side counts as 0 when the other side knows it")
        #expect(s.carbsG == nil && s.nicotineMg == nil)
    }

    @Test func scalesEveryField() {
        let n = Nutrition(kcal: 100, proteinG: 10, carbsG: 20, fatG: 4, caffeineMg: 0, nicotineMg: 1).scaled(by: 1.5)
        #expect(n == Nutrition(kcal: 150, proteinG: 15, carbsG: 30, fatG: 6, caffeineMg: 0, nicotineMg: 1.5))
    }

    @Test func typedValuesWinWhenFilling() {
        let typed = Nutrition(kcal: 408, proteinG: 8, caffeineMg: 0)
        let library = Nutrition(kcal: 400, proteinG: 9, carbsG: 60, fatG: 12, caffeineMg: 0, nicotineMg: 0)
        #expect(typed.filling(from: library) == Nutrition(kcal: 408, proteinG: 8, carbsG: 60, fatG: 12, caffeineMg: 0, nicotineMg: 0))
    }
}

@Suite struct HalfLifeTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func halvesEveryHalfLife() {
        let m = HalfLifeModel.caffeine
        let doses = [Dose(at: t0, mg: 200)]
        #expect(m.remaining(doses, at: t0) == 200)
        #expect(abs(m.remaining(doses, at: t0.addingTimeInterval(5 * 3600)) - 100) < 1e-9)
        #expect(abs(m.remaining(doses, at: t0.addingTimeInterval(10 * 3600)) - 50) < 1e-9)
    }

    @Test func futureDosesDoNotCountAndDosesAdd() {
        let m = HalfLifeModel.nicotine
        let doses = [Dose(at: t0, mg: 2), Dose(at: t0.addingTimeInterval(2 * 3600), mg: 2), Dose(at: t0.addingTimeInterval(9 * 3600), mg: 5)]
        #expect(abs(m.remaining(doses, at: t0.addingTimeInterval(2 * 3600)) - 3) < 1e-9)
    }

    @Test func curveHasOnePointPerStep() {
        let pts = HalfLifeModel.caffeine.curve([Dose(at: t0, mg: 100)], from: t0, to: t0.addingTimeInterval(3600), step: 600)
        #expect(pts.count == 7)
        #expect(pts.first?.1 == 100)
        #expect(pts.map(\.1) == pts.map(\.1).sorted(by: >))
    }
}

@Suite struct BaselineTests {
    @Test func skipsNotLoggedDaysAndNeedsEnoughData() {
        #expect(Baseline([1, 2, nil, 3, nil, 4, 5, 6]) == nil, "6 logged days is below the 7-day minimum")
        let b = try! #require(Baseline([1, 2, nil, 3, 4, 5, 6, 7, nil]))
        #expect(b.days == 7 && b.mean == 4 && b.median == 4)
        #expect(Baseline([1, 2, 3, 4], minimumDays: 4)?.median == 2.5)
    }

    @Test func headlinesAreNeutral() {
        let b = Baseline([300, 300, 300, 300, 300, 300, 300])!
        let fmt = { (m: Double) in Durations.compact(minutes: Int(m.rounded())) }
        #expect(Headline.comparison(320, to: b, format: fmt) == "about your 4-week average")
        #expect(Headline.comparison(340, to: b, format: fmt) == "40m above your 4-week average")
        #expect(Headline.comparison(370, to: b, format: fmt) == "1h 10m above your 4-week average")
        #expect(Headline.comparison(200, to: b, format: fmt) == "1h 40m below your 4-week average")
        #expect(Headline.comparison(200, to: nil, format: fmt) == nil)
    }
}

@Suite struct GapsTests {
    let t0 = Date(timeIntervalSince1970: 0)
    func i(_ a: Double, _ b: Double) -> DateInterval { DateInterval(start: t0.addingTimeInterval(a * 3600), end: t0.addingTimeInterval(b * 3600)) }

    @Test func findsUncoveredStretches() {
        let gaps = Gaps.unlogged(in: i(0, 24), covered: [i(1, 9), i(10, 12), i(11, 13), i(20, 26)], minimum: 30 * 60)
        #expect(gaps == [i(0, 1), i(9, 10), i(13, 20)])
    }

    @Test func ignoresShortGaps() {
        #expect(Gaps.unlogged(in: i(0, 2), covered: [i(0, 0.9), i(1.1, 2)], minimum: 30 * 60).isEmpty)
    }
}

@Suite struct NutritionFormatTests {
    @Test func summaryLeavesOutUnknownsAndRoundsKcal() {
        #expect(NutritionFormat.summary(Nutrition(kcal: 489.6, proteinG: 9.6)) == "490 kcal · 9.6 g protein")
        #expect(NutritionFormat.summary(Nutrition()) == "needs values")
    }

    @Test func compactIsDenseAndHidesZeroStimulants() {
        let n = Nutrition(kcal: 489.6, proteinG: 9.6, carbsG: 74.4, fatG: 14.4, caffeineMg: 0, nicotineMg: 0)
        #expect(NutritionFormat.compact(n) == "490 kcal · P 9.6 · C 74 · F 14")
        #expect(NutritionFormat.compact(Nutrition(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, caffeineMg: 0, nicotineMg: 1.2)) == "1.2 mg nicotine")
        #expect(NutritionFormat.compact(Nutrition(caffeineMg: 0)) == "0 kcal")
        #expect(NutritionFormat.compact(Nutrition()) == "needs values")
    }
}

@Suite struct SleepTimingTests {
    let tz = TimeZone(identifier: "Asia/Kolkata")!

    func at(_ d: Int, _ h: Int, _ m: Int) -> Date {
        Calendar.gregorian(in: tz).date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    @Test func medianWrapsAroundMidnight() {
        // 23:30, 00:15, 00:45, 01:15, 02:00 → median 00:45
        let starts = [at(1, 23, 30), at(2, 0, 15), at(3, 0, 45), at(4, 1, 15), at(5, 2, 0)]
        #expect(SleepTiming.usualOnset(starts, in: tz) == 45)
        let early = [at(1, 22, 0), at(2, 22, 30), at(3, 23, 0), at(4, 23, 30), at(5, 23, 0)]
        #expect(SleepTiming.usualOnset(early, in: tz) == -60)
        #expect(SleepTiming.usualOnset(Array(starts.prefix(4)), in: tz) == nil, "needs 5 nights")
    }

    @Test func bedtimeIsTheComingNight() {
        let day = LogicalDay("2026-11-09")!
        #expect(SleepTiming.bedtime(endingDay: day, onset: 45, in: tz) == at(10, 0, 45))
        #expect(SleepTiming.bedtime(endingDay: day, onset: -60, in: tz) == at(9, 23, 0))
    }
}

@Suite struct IntervalsTests {
    let t0 = Date(timeIntervalSince1970: 0)
    func i(_ a: Double, _ b: Double) -> DateInterval { DateInterval(start: t0.addingTimeInterval(a * 3600), end: t0.addingTimeInterval(b * 3600)) }

    @Test func overlapCountsSharedTimeOnce() {
        // Planned 10–13 and 14–16; did 10:30–12 and 11–12:30 (overlapping), 15–17.
        let planned = [i(10, 13), i(14, 16)]
        let actual = [i(10.5, 12), i(11, 12.5), i(15, 17)]
        #expect(Intervals.overlap(planned, actual) == 3 * 3600)
        #expect(Intervals.total(actual) == 4 * 3600)
        #expect(Intervals.union(actual) == [i(10.5, 12.5), i(15, 17)])
    }
}
