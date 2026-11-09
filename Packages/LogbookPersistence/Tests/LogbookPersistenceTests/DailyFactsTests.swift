import Foundation
import GRDB
import LogbookCore
import SQLiteData
import Testing
@testable import LogbookPersistence

/// `daily_facts` against a small synthetic day shaped like the Notes log.
@Suite struct DailyFactsTests {
    let env = TestEnv(start: Date(timeIntervalSince1970: 0))

    /// 10 Oct: two work blocks (60 + 150 min), sleep 00:45–09:30 (525 min),
    /// one NC block (78 min), three foods (one without values), burn and steps.
    func seededStore() throws -> LogStore {
        env.set(env.at(2026, 10, 10, 23, 0))
        let store = try env.store()
        try store.addBlock(kind: .work, start: env.at(2026, 10, 10, 9, 45), end: env.at(2026, 10, 10, 10, 45), label: "study + exam")
        try store.addBlock(kind: .work, start: env.at(2026, 10, 10, 11, 0), end: env.at(2026, 10, 10, 13, 30), label: "project horizon")
        try store.addBlock(kind: .sleep, start: env.at(2026, 10, 10, 0, 45), end: env.at(2026, 10, 10, 9, 30))
        try store.addBlock(kind: .natureCall, start: env.at(2026, 10, 10, 15, 50), end: env.at(2026, 10, 10, 17, 8))
        try store.logFood(name: "pulao 250g", nutrition: Nutrition(kcal: 408, proteinG: 8, caffeineMg: 0), consumedAt: env.at(2026, 10, 10, 14, 0))
        try store.logFood(name: "coffee", nutrition: Nutrition(kcal: 40, proteinG: 1, caffeineMg: 110), consumedAt: env.at(2026, 10, 10, 16, 0), isEstimate: true)
        try store.logFood(name: "Chicken roll", consumedAt: env.at(2026, 10, 10, 20, 0))
        try store.recordMetric(key: "active_kcal", value: 373, day: day("2026-10-10"))
        try store.recordMetric(key: "steps", value: 11_773, day: day("2026-10-10"))
        return store
    }

    @Test func aggregatesOneDay() throws {
        let store = try seededStore()
        let facts = try store.dailyFacts(from: day("2026-10-10"), through: day("2026-10-10"))
        let f = try #require(facts.first)
        #expect(f.workMin == 210)
        #expect(f.workBlocks == 2)
        #expect(f.sleepMin == 525)
        #expect(f.ncCount == 1)
        #expect(f.ncMin == 78)
        #expect(f.kcal == 448)
        #expect(f.proteinG == 9)
        #expect(f.caffeineMg == 110)
        #expect(f.foodEntries == 3)
        #expect(f.foodNeedingValues == 1)
        #expect(f.burnKcal == 373)
        #expect(f.steps == 11_773)
        #expect(f.netKcal == 75)
        #expect(f.hasEstimate)
    }

    @Test func notLoggedIsNilNotZero() throws {
        env.set(env.at(2026, 10, 11, 12, 0))
        let store = try env.store()
        try store.logFood(name: "pulao", nutrition: Nutrition(kcal: 408, proteinG: 8, caffeineMg: 0))
        let f = try #require(try store.dailyFacts(from: day("2026-10-11"), through: day("2026-10-11")).first)
        #expect(f.kcal == 408)
        #expect(f.workMin == nil)
        #expect(f.sleepMin == nil)
        #expect(f.ncCount == nil)
        #expect(f.burnKcal == nil)
        #expect(f.netKcal == nil, "net needs both intake and burn")
        #expect(!f.hasEstimate)
    }

    @Test func rangesHaveExplicitGaps() throws {
        let store = try seededStore()
        let facts = try store.dailyFacts(from: day("2026-10-09"), through: day("2026-10-12"))
        #expect(facts.map(\.logicalDay.description) == ["2026-10-09", "2026-10-10", "2026-10-11", "2026-10-12"])
        #expect(facts.map(\.isEmpty) == [true, false, true, true])
    }

    @Test func runningAndDeletedBlocksDoNotCount() throws {
        let store = try seededStore()
        env.set(env.at(2026, 10, 10, 18, 0))
        try store.startBlock(kind: .work)
        let extra = try store.addBlock(kind: .work, start: env.at(2026, 10, 10, 14, 0), end: env.at(2026, 10, 10, 15, 0))
        try store.deleteBlock(id: extra.id)
        let f = try #require(try store.dailyFacts(from: day("2026-10-10"), through: day("2026-10-10")).first)
        #expect(f.workMin == 210)
        #expect(f.workBlocks == 2)
    }

    @Test func overnightWorkUnderA4AMBoundaryCountsTowardThePreviousDay() throws {
        env.set(env.at(2026, 10, 10, 12, 0))
        let store = try env.store(boundary: DayBoundary(hour: 4))
        try store.addBlock(kind: .work, start: env.at(2026, 10, 9, 22, 50), end: env.at(2026, 10, 10, 0, 0))
        try store.addBlock(kind: .work, start: env.at(2026, 10, 10, 1, 0), end: env.at(2026, 10, 10, 3, 30))
        try store.addBlock(kind: .sleep, start: env.at(2026, 10, 10, 5, 15), end: env.at(2026, 10, 10, 10, 55))
        let facts = try store.dailyFacts(from: day("2026-10-09"), through: day("2026-10-10"))
        #expect(facts[0].workMin == 70 + 150)
        #expect(facts[0].sleepMin == nil)
        #expect(facts[1].workMin == nil)
        #expect(facts[1].sleepMin == 340)
    }

    @Test func customMetricAggregationLastTakesTheLatestSample() throws {
        env.set(env.at(2026, 10, 10, 8, 0))
        let store = try env.store()
        try store.database.write { db in
            try MetricDefinition.insert {
                MetricDefinition(id: env.nextUUID(), key: "weight", name: "Weight", unit: "kg", aggregation: .last, createdAt: env.now, updatedAt: env.now)
            }.execute(db)
        }
        try store.recordMetric(key: "weight", value: 71.2)
        env.advance(minutes: 600)
        try store.recordMetric(key: "weight", value: 70.8)
        let v = try store.database.read { db in
            try Double.fetchOne(db, sql: "SELECT value FROM daily_metric WHERE metric_key = 'weight' AND logical_day = '2026-10-10'")
        }
        #expect(v == 70.8)
    }
}
