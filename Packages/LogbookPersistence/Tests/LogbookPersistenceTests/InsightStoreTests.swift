import Foundation
import GRDB
import LogbookCore
import Testing
@testable import LogbookPersistence

@Suite struct InsightStoreTests {
    let env = TestEnv(start: Date(timeIntervalSince1970: 0))

    @Test func contextMirrorsTheLog() throws {
        env.set(env.at(2026, 11, 9, 20, 0))
        let s = try env.store()
        try s.addBlock(kind: .work, start: env.at(2026, 11, 8, 9, 0), end: env.at(2026, 11, 8, 12, 0))
        try s.addBlock(kind: .sleep, start: env.at(2026, 11, 8, 0, 30), end: env.at(2026, 11, 8, 8, 0))
        try s.logFood(name: "coffee", nutrition: Nutrition(kcal: 40, caffeineMg: 110), consumedAt: env.at(2026, 11, 8, 9, 0))
        try s.logFood(name: "late coffee", nutrition: Nutrition(kcal: 40, caffeineMg: 110), consumedAt: env.at(2026, 11, 8, 21, 0))
        let plan = try s.addPlanBlock(kind: .work, start: env.at(2026, 11, 9, 10, 0), end: env.at(2026, 11, 9, 11, 0))
        env.set(env.at(2026, 11, 9, 10, 25))
        try s.startPlanned(id: plan.id)
        let deck = try s.addTask(NewTask(title: "deck", listName: "horizon", estimateMin: 30))
        try s.addBlock(kind: .work, start: env.at(2026, 11, 7, 9, 0), end: env.at(2026, 11, 7, 9, 45))
        try s.database.write { db in try db.execute(sql: "UPDATE time_block SET task_id = ? WHERE start_utc = ?", arguments: [deck.id.uuidString.lowercased(), "2026-11-07 03:30:00.000"]) }
        try s.completeTask(id: deck.id)
        try s.addTask(NewTask(title: "big", scheduled: LogicalDay("2026-11-10"), estimateMin: 240))
        try s.addPlanBlock(kind: .work, start: env.at(2026, 11, 10, 10, 0), end: env.at(2026, 11, 10, 12, 0))

        let c = try s.insightContext(days: 10)
        #expect(c.days.count == 10 && c.days.last == LogicalDay("2026-11-09"))
        #expect(c.series("work")[8] == 180)
        #expect(c.series("sleep")[8] == 450)
        #expect(c.lastCaffeine[8] == env.at(2026, 11, 8, 21, 0))
        #expect(c.lastCaffeine[7] == nil && c.anyLogged[7] && !c.anyLogged[6])
        #expect(c.sleepStarts == [env.at(2026, 11, 8, 0, 30)])
        #expect(c.plan.startDrifts.map { $0.rounded() } == [25])
        #expect(c.plan.estimateRatios["horizon"] == [1.5])
        #expect(c.plan.tomorrowTaskMinutes == 240 && c.plan.tomorrowPlannedWorkMinutes == 120)
    }

    @Test func memoryRoundTrip() throws {
        env.set(env.at(2026, 11, 9, 20, 0))
        let s = try env.store()
        let i = Insight(detectorID: "trend", detectorVersion: 1, subjectKey: "sleep", kind: .trend, title: "t",
                        explanation: [], effect: 2, confidence: .high, pValue: nil, domain: "sleep")
        try s.markShown([i])
        try s.markShown([i]) // same day: counted once
        try s.dismiss(i)
        try s.snooze(i, days: 3)
        let m = try #require(try s.insightMemory().first)
        #expect(m.dismissedAt == env.now && m.dismissedEffect == 2)
        #expect(m.snoozedUntil == env.now.addingTimeInterval(3 * 86_400))
        let shown = try s.database.read { try Int.fetchOne($0, sql: "SELECT times_shown FROM insight_memory")! }
        #expect(shown == 1)
        #expect(try s.insightMemory().count == 1, "one row per detector + subject")
    }

    @Test func notificationLog() throws {
        env.set(env.at(2026, 11, 9, 20, 0))
        let s = try env.store()
        let a = UUID(), b = UUID()
        try s.logNotification(id: a, kind: "close-day", requested: false, fireAt: env.at(2026, 11, 9, 21, 0))
        try s.logNotification(id: b, kind: "close-day", requested: false, fireAt: env.at(2026, 11, 10, 21, 0))
        try s.markNotification(id: a, acted: "open")
        try s.forgetUnfiredNotifications(after: env.now)
        let log = try s.notificationLog(since: env.at(2026, 11, 1, 0, 0))
        #expect(log.map(\.id) == [a] && log.first?.action == "open" && log.first?.deliveredAt != nil)
    }
}
