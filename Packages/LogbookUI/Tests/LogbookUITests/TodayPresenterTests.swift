import Foundation
import LogbookCore
import LogbookPersistence
import Testing
@testable import LogbookUI

@Suite struct TodayPresenterTests {
    nonisolated static let tz = TimeZone(identifier: "Asia/Kolkata")!
    let cal = Calendar.gregorian(in: TodayPresenterTests.tz)
    let day = LogicalDay("2026-11-09")!

    func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    /// A store whose clock is pinned to 9 Nov 18:00.
    func store(now: Date) throws -> LogStore {
        LogStore(database: try AppDatabase.openInMemory(), now: { now }, timeZone: { Self.tz })
    }

    func present(_ store: LogStore, now: Date) throws -> TodayState {
        TodayPresenter(timeZone: Self.tz).present(try store.snapshot(of: day, in: Self.tz), now: now)
    }

    func hero(_ s: TodayState, _ id: String) -> TodayState.Hero { s.heroes.first { $0.id == id }! }

    @Test func emptyDayShowsDashesNotZeros() throws {
        let now = at(9, 18)
        let s = try present(try store(now: now), now: now)
        #expect(s.heroes.map(\.id) == ["work", "kcal", "protein", "caffeine", "nicotine", "sleep"])
        #expect(hero(s, "work").value == "—")
        #expect(hero(s, "kcal").value == "—")
        #expect(hero(s, "sleep").value == "—")
        #expect(hero(s, "work").headline == nil)
        #expect(s.title == "Monday, 9 November")
    }

    @Test func heroesComputeFromTheLog() throws {
        let now = at(9, 18)
        let store = try store(now: now)
        // Four weeks of 5h work days for a baseline.
        for d in 1...28 {
            let base = cal.date(byAdding: .day, value: -d, to: at(9, 10))!
            try store.addBlock(kind: .work, start: base, end: base.addingTimeInterval(5 * 3600))
        }
        try store.addBlock(kind: .sleep, start: at(8, 23, 30), end: at(9, 7, 0))
        try store.addBlock(kind: .work, start: at(9, 9), end: at(9, 12))
        try store.startBlock(kind: .work, label: "deep work") // started 18:00, 0 min so far
        try store.logFood(name: "coffee", nutrition: Nutrition(kcal: 40, proteinG: 1, caffeineMg: 200), consumedAt: at(9, 8))
        try store.logFood(name: "cig", nutrition: Nutrition(kcal: 0, nicotineMg: 2), consumedAt: at(9, 16))
        try store.logFood(name: "pulao", nutrition: Nutrition(kcal: 408, proteinG: 8, carbsG: 62, fatG: 12), consumedAt: at(9, 13))
        try store.recordMetric(key: "active_kcal", value: 300, day: day)

        let later = at(9, 18, 30)
        let s = try present(store, now: later)
        #expect(hero(s, "work").value == "3h 30m", "3h logged + 30m running")
        #expect(hero(s, "work").headline == "1h 30m below your 4-week average")
        #expect(hero(s, "kcal").title == "Net kcal")
        #expect(hero(s, "kcal").value == "148")
        #expect(hero(s, "kcal").detail == "448 in − 300 logged burn")
        #expect(hero(s, "protein").value == "9")
        // 200 mg at 08:00, 5 h half-life → 2 halvings at 18:00 → 50 mg; +30 min more.
        #expect(hero(s, "caffeine").value == String(Int((200 * pow(0.5, 10.5 / 5)).rounded())), "whole mg")
        #expect(hero(s, "nicotine").value == NutritionFormat.number(2 * pow(0.5, 2.5 / 2)))
        #expect(hero(s, "sleep").value == "7h 30m")
        #expect(s.foodTotals.map(\.label) == ["kcal", "protein", "carbs", "fat", "caffeine", "nicotine"])
        #expect(s.running.map(\.title) == ["deep work"])
        #expect(!s.running[0].looksForgotten)
    }

    @Test func trackClipsToTheDayAndRunsToNow() throws {
        let now = at(9, 18)
        let store = try store(now: at(9, 6))
        try store.addBlock(kind: .sleep, start: at(8, 23), end: at(9, 7))
        try store.startBlock(kind: .work)
        let s = try present(store, now: now)
        let sleep = try #require(s.track.first { $0.domain == .sleep })
        #expect(sleep.start == s.window.start, "last night's sleep is clipped at midnight")
        let work = try #require(s.track.first { $0.domain == .work })
        #expect(work.isRunning && work.end == now)
    }

    @Test func forgottenTimersAreFlagged() throws {
        let store = try store(now: at(9, 2))
        try store.startBlock(kind: .natureCall)
        let s = try present(store, now: at(9, 5))
        #expect(s.running.first?.looksForgotten == true)
    }

    @Test func closeTheDayListsWhatIsMissing() throws {
        let now = at(9, 18)
        let store = try store(now: now)
        try store.addBlock(kind: .sleep, start: at(9, 0, 30), end: at(9, 8))
        try store.addBlock(kind: .work, start: at(9, 8, 10), end: at(9, 12))
        try store.addBlock(kind: .work, start: at(9, 14), end: at(9, 17, 50))
        try store.logFood(name: "Chicken roll", consumedAt: at(9, 13))
        try store.recordMetric(key: "steps", value: 9000, day: day)
        let c = try present(store, now: now).closeDay
        #expect(c.gaps.map(\.text) == ["12:00–14:00 · 2h"], "short gaps (10 min) are ignored")
        #expect(c.missingBurn && !c.missingSteps)
        #expect(c.foodsNeedingValues.map(\.name) == ["Chicken roll"])
        #expect(!c.isComplete)
    }
}
