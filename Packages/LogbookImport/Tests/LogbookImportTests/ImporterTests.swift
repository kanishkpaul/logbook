import Foundation
import GRDB
import LogbookCore
import LogbookPersistence
import SQLiteData
import Synchronization
import Testing
@testable import LogbookImport

/// End to end on the synthetic fixture: preview → apply → re-run → undo.
@Suite struct ImporterTests {
    static let tz = TimeZone(identifier: "Asia/Kolkata")!

    func makeImporter(database: (any DatabaseWriter)? = nil) throws -> Importer {
        let db = try database ?? AppDatabase.openInMemory()
        let now = Calendar.gregorian(in: Self.tz).date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
        let store = LogStore(
            database: db, boundary: .standard, now: { now }, timeZone: { Self.tz },
            uuid: { [counter = Counter()] in counter.nextUUID() }
        )
        return Importer(store: store, timeZone: Self.tz, defaultYear: 2026)
    }

    func fixture() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "sample-log", withExtension: "md", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func count(_ importer: Importer, _ table: String) throws -> Int {
        try importer.store.database.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM \"\(table)\"")! }
    }

    func day(_ s: String) -> LogicalDay { LogicalDay(s)! }

    // MARK: Preview

    @Test func previewCountsEverythingAndWritesNothing() throws {
        let importer = try makeImporter()
        let plan = try importer.preview(try fixture(), sourceName: "sample-log.md")
        #expect(plan.blocks.count == 9)
        #expect(plan.foodEntries.count == 7)
        #expect(plan.samples.count == 4)
        #expect(plan.newFoods.map(\.name).sorted() == ["coffee", "paneer", "pulao"])
        #expect(plan.days.map(\.day.description) == ["2026-10-09", "2026-10-10"])
        #expect(plan.errors.isEmpty)
        #expect(try count(importer, "time_block") == 0)
        #expect(try count(importer, "food") == 0)
        #expect(try count(importer, "import_batch") == 0)
    }

    @Test func typedTotalsAreChecksAndMismatchesAreWarnings() throws {
        let plan = try makeImporter().preview(try fixture(), sourceName: "sample-log.md")
        let codes = plan.issues.map(\.code)
        // 9 Oct: work 5h 10m, intake 978/45/110 and net 678 all match → no warnings.
        #expect(!plan.issues.contains { $0.day == day("2026-10-09") && $0.severity == .warning })
        // 10 Oct: $ 3h 20m vs 3h 30m of blocks, and nc [10m] vs 8 minutes.
        #expect(codes.filter { $0 == .workTotalMismatch }.count == 1)
        #expect(codes.filter { $0 == .typedDurationMismatch }.count == 1)
        #expect(codes.filter { $0 == .valuesFromLibrary }.count == 2)
        #expect(codes.filter { $0 == .needsValues }.count == 1)
        #expect(!codes.contains(.nutritionTotalMismatch))
    }

    // MARK: Apply

    @Test func applyMatchesTheNotesTotals() throws {
        let importer = try makeImporter()
        let plan = try importer.preview(try fixture(), sourceName: "sample-log.md")
        try importer.apply(plan)

        let facts = try importer.store.dailyFacts(from: day("2026-10-09"), through: day("2026-10-10"))
        let d9 = facts[0], d10 = facts[1]
        #expect(d9.workMin == 310)
        #expect(d9.workBlocks == 3)
        #expect(d9.sleepMin == 450)
        #expect(d9.ncCount == 1 && d9.ncMin == 78)
        #expect(d9.kcal == 978 && d9.proteinG == 45 && d9.caffeineMg == 110)
        #expect(d9.burnKcal == 300 && d9.steps == 9000)
        #expect(d9.netKcal == 678)
        #expect(!d9.hasEstimate)

        #expect(d10.workMin == 210)
        #expect(d10.sleepMin == 340)
        #expect(d10.ncMin == 8)
        // pulao 300g from the 250 g library serving (×1.2) + thali + coffee from the library.
        #expect(abs((d10.kcal ?? 0) - (408 * 1.2 + 1290 + 40)) < 0.001)
        #expect(d10.foodNeedingValues == 1)
        #expect(d10.hasEstimate)
    }

    @Test func importedRowsKeepProvenance() throws {
        let importer = try makeImporter()
        let plan = try importer.preview(try fixture(), sourceName: "sample-log.md")
        try importer.apply(plan)
        let sleep = try importer.store.database.read { db in
            try TimeBlock.where { $0.kind.eq(BlockKind.sleep) }.order(by: \.startUTC).fetchAll(db)
        }
        #expect(sleep.first?.rawText == "sleep -> 0100 - 0830 [7h 30m]")
        #expect(sleep.first?.source == .import)
        #expect(sleep.first?.importBatchID == plan.batch.id)
        // 01:00 IST on 9 Oct is 19:30 UTC on 8 Oct.
        #expect(sleep.first?.startUTC == ISO8601DateFormatter().date(from: "2026-10-08T19:30:00Z"))
        let pulao = try importer.store.database.read { db in
            try Food.where { $0.name.eq("pulao") }.fetchOne(db)
        }
        #expect(pulao?.servingSize == 250 && pulao?.servingUnit == "g" && pulao?.kcal == 408)
    }

    @Test func reRunningTheSameFileAddsNothing() throws {
        let importer = try makeImporter()
        try importer.apply(try importer.preview(try fixture(), sourceName: "sample-log.md"))
        let again = try importer.preview(try fixture(), sourceName: "sample-log.md")
        #expect(again.rowCount == 0)
        #expect(again.newFoods.isEmpty)
        #expect(again.alreadyImported == 20)
        try importer.apply(again)
        #expect(try count(importer, "time_block") == 9)
        #expect(try count(importer, "food_log_entry") == 7)
    }

    @Test func manuallyLoggedBlocksAreNotDuplicated() throws {
        let importer = try makeImporter()
        let cal = Calendar.gregorian(in: Self.tz)
        try importer.store.addBlock(
            kind: .work,
            start: cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 9, minute: 30))!,
            end: cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 11, minute: 0))!,
            label: "study"
        )
        let plan = try importer.preview(try fixture(), sourceName: "sample-log.md")
        #expect(plan.blocks.count == 8)
        #expect(plan.issues.contains { $0.code == .likelyDuplicate })
    }

    @Test func existingLibraryFoodsAndAliasesFillMissingValues() throws {
        let importer = try makeImporter()
        let roll = try importer.store.addFood(name: "Kathi roll", nutrition: Nutrition(kcal: 350, proteinG: 14, caffeineMg: 0))
        try importer.store.database.write { db in
            try db.execute(sql: "UPDATE food SET aliases = ? WHERE id = ?", arguments: ["[\"chicken roll\"]", roll.id.uuidString.lowercased()])
        }
        let plan = try importer.preview(try fixture(), sourceName: "sample-log.md")
        let entry = try #require(plan.foodEntries.first { $0.name == "Chicken roll" })
        #expect(entry.kcal == 350)
        #expect(entry.foodID == roll.id)
        #expect(entry.isEstimate)
        #expect(!plan.issues.contains { $0.code == .needsValues })
    }

    // MARK: Undo

    @Test func undoRestoresTheDatabaseAndKeepsAnAuditTrail() throws {
        let importer = try makeImporter()
        let plan = try importer.preview(try fixture(), sourceName: "sample-log.md")
        try importer.apply(plan)
        try importer.undo(batchID: plan.batch.id)

        for table in ["time_block", "food_log_entry", "metric_sample", "food"] {
            #expect(try count(importer, table) == 0, "\(table) should be empty after undo")
        }
        let batch = try #require(try importer.batches().first)
        #expect(batch.undoneAt != nil)
        let deletes = try importer.store.database.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM change_log WHERE action = 'delete'")! }
        #expect(deletes == 9 + 7 + 4 + 3)
        #expect(throws: Importer.Failure.alreadyUndone(plan.batch.id)) { try importer.undo(batchID: plan.batch.id) }

        // The same file can be imported again afterwards.
        let again = try importer.preview(try fixture(), sourceName: "sample-log.md")
        #expect(again.rowCount == 20)
        #expect(again.newFoods.count == 3)
    }

    @Test func undoKeepsLibraryFoodsThatOtherEntriesUse() throws {
        let importer = try makeImporter()
        let plan = try importer.preview(try fixture(), sourceName: "sample-log.md")
        try importer.apply(plan)
        let pulao = try #require(try importer.store.database.read { db in try Food.where { $0.name.eq("pulao") }.fetchOne(db) })
        try importer.store.logFood(name: "pulao", food: pulao)
        try importer.undo(batchID: plan.batch.id)
        #expect(try count(importer, "food") == 1)
        #expect(try count(importer, "food_log_entry") == 1)
    }

    @Test func undoUnknownBatchFails() throws {
        let importer = try makeImporter()
        let id = UUID()
        #expect(throws: Importer.Failure.batchNotFound(id)) { try importer.undo(batchID: id) }
    }

    // MARK: Ids

    @Test func stableIDsAreDeterministicAndWellFormed() {
        let a = ImportPlanner.stableUUID("x"), b = ImportPlanner.stableUUID("x"), c = ImportPlanner.stableUUID("y")
        #expect(a == b && a != c)
        let s = a.uuidString
        #expect(s[s.index(s.startIndex, offsetBy: 14)] == "5")
        #expect("89AB".contains(s[s.index(s.startIndex, offsetBy: 19)]))
    }
}

/// Sequential UUIDs for deterministic tests.
final class Counter: Sendable {
    let value = Mutex<UInt64>(0)
    func nextUUID() -> UUID {
        let n = value.withLock { c -> UInt64 in c += 1; return c }
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", n))!
    }
}
