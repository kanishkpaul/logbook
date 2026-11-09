import Foundation
import GRDB
import LogbookCore
import SQLiteData
import Testing
@testable import LogbookPersistence

@Suite struct LogStoreTests {
    let env = TestEnv(start: Date(timeIntervalSince1970: 0))

    // MARK: Timers

    @Test func timerRunsUntilStoppedAndElapsedComesFromInstants() throws {
        env.set(env.at(2026, 10, 10, 9, 45))
        let store = try env.store()
        let started = try store.startBlock(kind: .work, label: "study")
        #expect(started.isRunning)
        #expect(try store.runningBlocks().map(\.id) == [started.id])

        env.advance(minutes: 60)
        let stopped = try store.stopBlock(id: started.id)
        #expect(stopped.endUTC == env.at(2026, 10, 10, 10, 45))
        #expect(Durations.minutes(from: stopped.startUTC, to: stopped.endUTC!) == 60)
        #expect(try store.runningBlocks().isEmpty)
    }

    @Test func onlyOneRunningBlockPerKind() throws {
        env.set(env.at(2026, 10, 10, 9, 0))
        let store = try env.store()
        try store.startBlock(kind: .work)
        #expect(throws: LogStore.Failure.alreadyRunning(.work)) { try store.startBlock(kind: .work) }
        // A different kind can run at the same time.
        try store.startBlock(kind: .natureCall)
        #expect(try store.runningBlocks().count == 2)
    }

    @Test func stoppingSleepReattributesToTheWakeDay() throws {
        env.set(env.at(2026, 10, 9, 23, 30))
        let store = try env.store()
        let s = try store.startBlock(kind: .sleep)
        #expect(s.logicalDay == day("2026-10-09"))
        env.set(env.at(2026, 10, 10, 7, 15))
        #expect(try store.stopBlock(id: s.id).logicalDay == day("2026-10-10"))
    }

    @Test func stoppingTwiceFails() throws {
        let store = try env.store()
        let b = try store.startBlock(kind: .work)
        try store.stopBlock(id: b.id)
        #expect(throws: LogStore.Failure.notRunning(b.id)) { try store.stopBlock(id: b.id) }
    }

    // MARK: Attribution is fixed on write

    @Test func lateNightWorkUsesTheBoundaryInForceWhenWritten() throws {
        env.set(env.at(2026, 10, 10, 12, 0))
        var store = try env.store(boundary: DayBoundary(hour: 4))
        let late = try store.addBlock(kind: .work, start: env.at(2026, 10, 10, 1, 0), end: env.at(2026, 10, 10, 3, 30))
        #expect(late.logicalDay == day("2026-10-09"))

        // Switching to calendar days affects new rows only.
        store.boundary = .calendarDay
        let later = try store.addBlock(kind: .work, start: env.at(2026, 10, 11, 1, 0), end: env.at(2026, 10, 11, 2, 0))
        #expect(later.logicalDay == day("2026-10-11"))
        let stored = try store.database.read { try TimeBlock.find(late.id).fetchOne($0) }
        #expect(stored?.logicalDay == day("2026-10-09"))
    }

    @Test func retimingRecomputesAttribution() throws {
        let store = try env.store(boundary: DayBoundary(hour: 4))
        let b = try store.addBlock(kind: .work, start: env.at(2026, 10, 10, 9, 0), end: env.at(2026, 10, 10, 10, 0))
        #expect(b.logicalDay == day("2026-10-10"))
        let moved = try store.retime(id: b.id, start: env.at(2026, 10, 10, 2, 0), end: env.at(2026, 10, 10, 3, 0))
        #expect(moved.logicalDay == day("2026-10-09"))
    }

    @Test func endBeforeStartIsRejected() throws {
        let store = try env.store()
        #expect(throws: LogStore.Failure.endBeforeStart) {
            try store.addBlock(kind: .work, start: env.at(2026, 10, 10, 10, 0), end: env.at(2026, 10, 10, 9, 0))
        }
    }

    // MARK: Food snapshots

    @Test func editingTheLibraryNeverChangesHistory() throws {
        env.set(env.at(2026, 10, 10, 13, 0))
        let store = try env.store()
        let paneer = try store.addFood(name: "paneer", nutrition: Nutrition(kcal: 265, proteinG: 18, caffeineMg: 0), servingSize: 100, servingUnit: "g")
        let entry = try store.logFood(name: "paneer 200g", food: paneer, servings: 2, quantity: 200, unit: "g")
        #expect(entry.kcal == 530)
        #expect(entry.proteinG == 36)

        try store.updateFood(id: paneer.id, nutrition: Nutrition(kcal: 300, proteinG: 20, caffeineMg: 0))
        let stored = try store.database.read { try FoodLogEntry.find(entry.id).fetchOne($0) }
        #expect(stored?.kcal == 530)
        #expect(stored?.proteinG == 36)
    }

    @Test func explicitValuesWinAndMissingValuesAreNotZero() throws {
        let store = try env.store()
        let pulao = try store.logFood(name: "pulao 250g", nutrition: Nutrition(kcal: 408, proteinG: 8, caffeineMg: 0))
        #expect(pulao.kcal == 408 && !pulao.needsValues)
        let roll = try store.logFood(name: "Chicken roll")
        #expect(roll.needsValues)
        #expect(roll.kcal == nil)
    }

    // MARK: Metrics

    @Test func recordsBuiltinMetricsAndRejectsUnknownKeys() throws {
        env.set(env.at(2026, 10, 10, 22, 0))
        let store = try env.store()
        let s = try store.recordMetric(key: "steps", value: 11_773)
        #expect(s.metricID == Schema.BuiltinMetric.steps)
        #expect(s.logicalDay == day("2026-10-10"))
        #expect(throws: LogStore.Failure.unknownMetric("weight")) { try store.recordMetric(key: "weight", value: 70) }
    }

    // MARK: Change log

    @Test func changesAreRecordedWithBeforeAndAfter() throws {
        env.set(env.at(2026, 10, 10, 9, 0))
        let store = try env.store()
        let b = try store.addBlock(kind: .work, start: env.at(2026, 10, 10, 8, 0), end: env.at(2026, 10, 10, 9, 0), label: "study")
        env.advance(minutes: 5)
        try store.deleteBlock(id: b.id)
        let log = try store.database.read { db in
            try ChangeLogEntry.where { $0.tableName.eq("time_block") }.order(by: \.changedAt).fetchAll(db)
        }
        #expect(log.map(\.action) == ["insert", "update"])
        #expect(log[0].beforeJSON == nil)
        #expect(log[0].afterJSON?.contains("\"label\":\"study\"") == true)
        #expect(log[1].beforeJSON?.contains("\"deleted_at\":null") == true)
        #expect(log[1].afterJSON?.contains("\"deleted_at\":null") == false)
        #expect(log[1].changedAt == env.now)
    }
}
