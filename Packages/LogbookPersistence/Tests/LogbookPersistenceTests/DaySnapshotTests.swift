import Foundation
import GRDB
import LogbookCore
import SQLiteData
import Testing
@testable import LogbookPersistence

@Suite struct MacrosAndNicotineTests {
    let env = TestEnv(start: Date(timeIntervalSince1970: 0))

    @Test func dictionaryValuesAreSnapshottedAndTotalled() throws {
        env.set(env.at(2026, 11, 9, 13, 0))
        let store = try env.store()
        var paneer = store.newFood(name: "paneer")
        paneer.servingSize = 100
        paneer.servingUnit = "g"
        paneer.nutrition = Nutrition(kcal: 265, proteinG: 18, carbsG: 1.2, fatG: 20, caffeineMg: 0, nicotineMg: 0)
        try store.saveFood(paneer)
        var pouch = store.newFood(name: "nicotine pouch")
        pouch.nutrition = Nutrition(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, caffeineMg: 0, nicotineMg: 6)
        try store.saveFood(pouch)

        try store.logFood(name: "paneer 200g", food: paneer, servings: 2)
        try store.logFood(name: "pouch", food: pouch)
        try store.logFood(name: "pouch", food: pouch)

        let f = try #require(try store.dailyFacts(from: LogicalDay("2026-11-09")!, through: LogicalDay("2026-11-09")!).first)
        #expect(f.kcal == 530 && f.proteinG == 36)
        #expect(f.carbsG == 2.4 && f.fatG == 40)
        #expect(f.nicotineMg == 12)
        #expect(f.caffeineMg == 0)
    }

    @Test func v3KeepsOldRowsUnknownNotZero() throws {
        let queue = try DatabaseQueue()
        var migrator = Schema.migrator
        try migrator.migrate(queue, upTo: "v2: food import batch")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO food_log_entry (id, name, kcal, protein_g, caffeine_mg, consumed_at, tz_identifier, logical_day, created_at, updated_at)
                VALUES ('a', 'pulao', 408, 8, 0, '2026-10-10 06:30:00.000', 'Asia/Kolkata', '2026-10-10', '2026-10-10 06:30:00.000', '2026-10-10 06:30:00.000')
                """)
        }
        migrator = Schema.migrator
        try migrator.migrate(queue)
        let row = try queue.read { try Row.fetchOne($0, sql: "SELECT kcal, carbs_g, nicotine_mg FROM daily_facts")! }
        #expect(row["kcal"] as Double? == 408)
        #expect(row["carbs_g"] as Double? == nil)
        #expect(row["nicotine_mg"] as Double? == nil)
    }

    @Test func dictionaryOrderingArchivingAndAliases() throws {
        let store = try env.store()
        var a = store.newFood(name: "zucchini")
        a.isFavourite = true
        try store.saveFood(a)
        var b = store.newFood(name: "Apple")
        b.aliasList = ["  appl ", "", "sev"]
        try store.saveFood(b)
        try store.saveFood(store.newFood(name: "banana"))
        #expect(try store.dictionary().map(\.name) == ["zucchini", "Apple", "banana"])
        #expect(try store.dictionary().first { $0.name == "Apple" }?.aliasList == ["appl", "sev"])

        try store.archiveFood(id: a.id)
        #expect(try store.dictionary().map(\.name) == ["Apple", "banana"])
        #expect(try store.dictionary(includeArchived: true).count == 3)
    }

    @Test func savingAnEditedFoodUpdatesInPlace() throws {
        let store = try env.store()
        var food = try store.saveFood(store.newFood(name: "dal"))
        food.nutrition.kcal = 180
        try store.saveFood(food)
        #expect(try store.dictionary().map(\.kcal) == [180])
    }

    @Test func fillingValuesOnAnEntry() throws {
        let store = try env.store()
        let roll = try store.logFood(name: "Chicken roll")
        #expect(roll.needsValues)
        let filled = try store.updateFoodEntry(id: roll.id, nutrition: Nutrition(kcal: 350, proteinG: 14), isEstimate: true)
        #expect(!filled.needsValues && filled.isEstimate)
    }
}

@Suite struct DaySnapshotTests {
    let env = TestEnv(start: Date(timeIntervalSince1970: 0))
    let day = LogicalDay("2026-11-09")!

    func seeded() throws -> LogStore {
        env.set(env.at(2026, 11, 9, 18, 0))
        let store = try env.store()
        // Slept from the previous evening into today.
        try store.addBlock(kind: .sleep, start: env.at(2026, 11, 8, 23, 30), end: env.at(2026, 11, 9, 7, 0))
        try store.addBlock(kind: .work, start: env.at(2026, 11, 9, 9, 0), end: env.at(2026, 11, 9, 12, 0))
        // Yesterday's work, not overlapping today.
        try store.addBlock(kind: .work, start: env.at(2026, 11, 8, 9, 0), end: env.at(2026, 11, 8, 12, 0))
        try store.logFood(name: "late coffee", nutrition: Nutrition(kcal: 40, caffeineMg: 110), consumedAt: env.at(2026, 11, 8, 21, 0))
        try store.logFood(name: "coffee", nutrition: Nutrition(kcal: 40, caffeineMg: 110), consumedAt: env.at(2026, 11, 9, 10, 0))
        try store.logFood(name: "pulao", nutrition: Nutrition(kcal: 408, proteinG: 8), consumedAt: env.at(2026, 11, 9, 13, 0))
        try store.recordMetric(key: "steps", value: 9000, day: day)
        try store.startBlock(kind: .work, label: "deep work")
        return store
    }

    @Test func snapshotHoldsTheDay() throws {
        let store = try seeded()
        let s = try store.snapshot(of: day, in: env.tz)
        #expect(s.blocks.map(\.kind) == [.sleep, .work, .work], "sleep from last night overlaps today; running work included")
        #expect(s.running.map(\.label) == ["deep work"])
        #expect(s.foods.map(\.name) == ["coffee", "pulao"])
        #expect(s.doses.map(\.name) == ["late coffee", "coffee"], "doses reach back 24 h; pulao has none")
        #expect(s.samples.map(\.key) == ["steps"])
        #expect(s.history.count == 29)
        #expect(s.today.workMin == 180)
        #expect(s.today.sleepMin == 450)
        #expect(s.previous.last?.workMin == 180)
        #expect(s.window.duration == 24 * 3600)
    }

    @Test func observationEmitsAfterChanges() async throws {
        let store = try seeded()
        var iterator = store.observe(day, in: env.tz).makeAsyncIterator()
        let first = try await iterator.next()
        #expect(first?.foods.count == 2)
        try store.logFood(name: "banana", nutrition: Nutrition(kcal: 100), consumedAt: env.at(2026, 11, 9, 16, 0))
        let second = try await iterator.next()
        #expect(second?.foods.count == 3)
    }

    @Test func stoppingAtAChosenTime() throws {
        let store = try seeded()
        let running = try #require(try store.runningBlocks().first)
        #expect(throws: LogStore.Failure.endBeforeStart) { try store.stopBlock(id: running.id, at: running.startUTC.addingTimeInterval(-60)) }
        let stopped = try store.stopBlock(id: running.id, at: running.startUTC.addingTimeInterval(1800))
        #expect(Durations.minutes(from: stopped.startUTC, to: stopped.endUTC!) == 30)
    }
}
