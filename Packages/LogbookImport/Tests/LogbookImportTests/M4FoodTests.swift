import Foundation
import LogbookCore
import LogbookPersistence
import Testing
@testable import LogbookImport

@Suite struct M4FoodTests {
    static let tz = TimeZone(identifier: "Asia/Kolkata")!
    let cal = Calendar.gregorian(in: M4FoodTests.tz)

    func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    func make(now: Date) throws -> QuickEntry {
        QuickEntry(store: LogStore(database: try AppDatabase.openInMemory(), now: { now }, timeZone: { Self.tz }))
    }

    func log(_ q: QuickEntry, _ text: String) throws -> QuickEntry.Interpretation {
        let i = try q.interpret(text)
        try q.commit(i)
        return i
    }

    func today(_ q: QuickEntry) throws -> DaySnapshot {
        try q.store.snapshot(of: LogicalDay("2026-11-09")!, in: Self.tz)
    }

    // MARK: Counts

    @Test func countedItemsSeedOneServing() throws {
        let q = try make(now: at(9, 9))
        try log(q, "egg x2 - 140 / 12 / 0")
        let egg = try #require(try q.store.dictionary().first)
        #expect(egg.name == "egg" && egg.kcal == 70 && egg.proteinG == 6, "the dictionary stores one egg")
        let three = try q.interpret("3 eggs")
        #expect(three.lines[0].detail == "210 kcal · P 18", "leading counts and plurals resolve to the same entry")
    }

    // MARK: Copy yesterday

    @Test func copyYesterdayKeepsTimesAndValues() throws {
        let store = LogStore(database: try AppDatabase.openInMemory(), now: { self.at(8, 22) }, timeZone: { Self.tz })
        try store.logFood(name: "coffee", nutrition: Nutrition(kcal: 40, caffeineMg: 110), consumedAt: at(8, 9, 30))
        try store.logFood(name: "pulao", nutrition: Nutrition(kcal: 408, proteinG: 8), consumedAt: at(8, 13))
        let q = QuickEntry(store: LogStore(database: store.database, now: { self.at(9, 8) }, timeZone: { Self.tz }))
        let i = try q.interpret("copy yesterday")
        #expect(i.lines.first?.detail == "2 items · same times today")
        try q.commit(i)
        let foods = try today(q).foods
        #expect(foods.map(\.consumedAt) == [at(9, 9, 30), at(9, 13)])
        #expect(foods.map(\.kcal) == [40, 408])
        #expect(try q.interpret("copy yesterday").problem == nil)
        let empty = try make(now: at(9, 8))
        #expect(try empty.interpret("copy yesterday").problem == "Nothing was logged yesterday")
    }

    // MARK: Quick add

    @Test func quickAddListsFavouritesThenFrequentRecents() throws {
        let q = try make(now: at(9, 20))
        var coffee = q.store.newFood(name: "coffee")
        coffee.nutrition = Nutrition(kcal: 40, caffeineMg: 110)
        try q.store.saveFood(coffee)
        var dal = q.store.newFood(name: "dal")
        dal.isFavourite = true
        try q.store.saveFood(dal)
        for _ in 0..<3 { try log(q, "coffee") }
        try log(q, "Chicken roll")
        #expect(try q.store.quickAddNames() == ["dal", "coffee", "Chicken roll"])
    }

    // MARK: Meals

    @Test func defineAndLogAMeal() throws {
        let q = try make(now: at(9, 9))
        try log(q, "coffee - 40 / 1 / 110 / 0 / 5c / 1f")
        try log(q, "egg x2 - 140 / 12 / 0 / 0 / 1c / 10f")
        try log(q, "toast 2 slices - 160 / 6 / 0 / 0 / 30c / 2f")

        let define = try q.interpret("meal breakfast = coffee + 2 eggs + toast 2 slices")
        #expect(define.lines.first?.title == "Save meal “breakfast”")
        #expect(define.lines.first?.detail == "340 kcal · P 19 · C 36 · F 13 · 110 mg caffeine")
        try q.commit(define)
        #expect(try q.store.meals().map(\.meal.name) == ["breakfast"])

        let before = try today(q).foods.count
        let logged = try q.interpret("breakfast")
        #expect(logged.lines.first?.title == "Meal · breakfast")
        try q.commit(logged)
        let after = try today(q)
        #expect(after.foods.count == before + 3)
        #expect(after.foods.suffix(3).map(\.rawText) == Array(repeating: "meal: breakfast", count: 3))

        let double = try q.interpret("breakfast x2")
        #expect(double.lines.first?.detail == "680 kcal · P 38 · C 72 · F 26 · 220 mg caffeine")
    }

    @Test func redefiningReplacesAndUnknownPartsAreRefused() throws {
        let q = try make(now: at(9, 9))
        try log(q, "coffee - 40 / 1 / 110")
        try log(q, "meal quick = coffee")
        #expect(try q.interpret("meal quick = coffee x2").lines.first?.title == "Replace meal “quick”")
        try log(q, "meal quick = coffee x2")
        #expect(try q.store.meals().first?.items.first?.item.servings == 2)
        #expect(try q.interpret("meal lunch = coffee + mystery stew").problem?.contains("mystery stew") == true)
    }
}
