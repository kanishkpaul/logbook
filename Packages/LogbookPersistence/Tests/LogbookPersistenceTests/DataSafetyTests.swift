import Foundation
import GRDB
import LogbookCore
import SQLiteData
import Testing
@testable import LogbookPersistence

@Suite struct DataSafetyTests {
    let env = TestEnv(start: Date(timeIntervalSince1970: 0))

    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "logbook-tests-\(UUID().uuidString)")
    }

    /// A bit of everything: blocks (one deleted), food with values and without,
    /// a dictionary entry, metrics, and the change log those writes produced.
    func seeded() throws -> LogStore {
        env.set(env.at(2026, 11, 9, 20, 0))
        let store = try env.store()
        var paneer = store.newFood(name: "paneer, \"malai\"")
        paneer.servingSize = 100
        paneer.servingUnit = "g"
        paneer.aliasList = ["pnr"]
        paneer.nutrition = Nutrition(kcal: 265, proteinG: 18.3, carbsG: 1.2, fatG: 20, caffeineMg: 0, nicotineMg: 0)
        try store.saveFood(paneer)
        try store.addBlock(kind: .work, start: env.at(2026, 11, 9, 9, 0), end: env.at(2026, 11, 9, 12, 0), label: "study, with comma")
        let gone = try store.addBlock(kind: .work, start: env.at(2026, 11, 9, 13, 0), end: env.at(2026, 11, 9, 14, 0))
        try store.deleteBlock(id: gone.id)
        try store.logFood(name: "paneer 200g", food: paneer, servings: 2, quantity: 200, unit: "g")
        try store.logFood(name: "Chicken roll\nline two")
        try store.recordMetric(key: "steps", value: 9000)
        return store
    }

    // MARK: Backups

    @Test func snapshotIsAReadableCopy() throws {
        let store = try seeded()
        let backups = Backups(database: store.database, directory: tempDir())
        let url = try backups.backUp(day: LogicalDay("2026-11-09")!)
        #expect(url.lastPathComponent == "logbook-2026-11-09.sqlite")
        let copy = try DatabaseQueue(path: url.path)
        let blocks = try copy.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM time_block")! }
        #expect(blocks == 2)
    }

    @Test func dailyIsOncePerDayAndOldOnesArePruned() throws {
        let store = try seeded()
        let backups = Backups(database: store.database, directory: tempDir(), keep: 3)
        let day = LogicalDay("2026-11-01")!
        #expect(try backups.ensureDaily(day: day) != nil)
        #expect(try backups.ensureDaily(day: day) == nil, "second call the same day does nothing")
        for i in 1...4 { try backups.backUp(day: day.adding(days: i)) }
        #expect(backups.list().map(\.lastPathComponent) == ["logbook-2026-11-05.sqlite", "logbook-2026-11-04.sqlite", "logbook-2026-11-03.sqlite"])
    }

    // MARK: JSON

    @Test func jsonRoundTripReproducesTheDatabase() throws {
        let store = try seeded()
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let exported = try DataExport.json(store.database, exportedAt: at)

        let fresh = try AppDatabase.openInMemory()
        try DataExport.restore(exported, into: fresh)
        let again = try DataExport.json(fresh, exportedAt: at)
        #expect(String(decoding: again, as: UTF8.self) == String(decoding: exported, as: UTF8.self))

        // And the restored database answers the same questions.
        let restored = LogStore(database: fresh, now: { env.now }, timeZone: { env.tz })
        let d = LogicalDay("2026-11-09")!
        #expect(try restored.dailyFacts(from: d, through: d) == store.dailyFacts(from: d, through: d))
    }

    @Test func restoreRefusesANonEmptyDatabaseOrGarbage() throws {
        let store = try seeded()
        let exported = try DataExport.json(store.database, exportedAt: Date())
        #expect(throws: DataExport.RestoreError.targetNotEmpty) { try DataExport.restore(exported, into: store.database) }
        #expect(throws: DataExport.RestoreError.notAnExport) { try DataExport.restore(Data("{}".utf8), into: try AppDatabase.openInMemory()) }
    }

    // MARK: CSV

    @Test func csvQuotesAndIncludesDailyFacts() throws {
        let store = try seeded()
        let dir = tempDir()
        let files = try DataExport.csv(store.database, to: dir)
        #expect(files.map(\.lastPathComponent).contains("daily_facts.csv"))
        let blocks = try String(contentsOf: dir.appending(path: "time_block.csv"), encoding: .utf8)
        #expect(blocks.hasPrefix("id,kind,label,"))
        #expect(blocks.contains("\"study, with comma\""))
        let foods = try String(contentsOf: dir.appending(path: "food.csv"), encoding: .utf8)
        #expect(foods.contains("\"paneer, \"\"malai\"\"\""))
        let entries = try String(contentsOf: dir.appending(path: "food_log_entry.csv"), encoding: .utf8)
        #expect(entries.contains("\"Chicken roll\nline two\""))
        let facts = try String(contentsOf: dir.appending(path: "daily_facts.csv"), encoding: .utf8)
        #expect(facts.split(separator: "\n").count == 2, "header + one day")
    }
}
