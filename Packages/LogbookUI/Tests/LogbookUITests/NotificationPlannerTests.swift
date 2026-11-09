import Foundation
import LogbookCore
import LogbookPersistence
import Testing
@testable import LogbookUI

@Suite struct NotificationPlannerTests {
    nonisolated static let tz = TimeZone(identifier: "Asia/Kolkata")!
    let cal = Calendar.gregorian(in: NotificationPlannerTests.tz)
    let day = LogicalDay("2026-11-09")!
    let all = Set(NotificationKind.allCases)

    func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    /// Ten nights falling asleep at 01:00 → bedtime 01:00, caffeine cutoff 19:00.
    func store(now: Date) throws -> LogStore {
        let s = LogStore(database: try AppDatabase.openInMemory(), now: { now }, timeZone: { Self.tz })
        for k in 0..<10 { try s.addBlock(kind: .sleep, start: at(9 - k, 1), end: at(9 - k, 8)) }
        return s
    }

    func inputs(_ s: LogStore, now: Date, enabled: Set<NotificationKind>? = nil, log: [NotificationLogEntry] = [], insights: [Insight] = []) throws -> NotificationInputs {
        let snap = try s.snapshot(of: day, in: Self.tz)
        let tomorrow = try s.snapshot(of: day.next, in: Self.tz)
        return NotificationInputs(now: now, timeZone: Self.tz, today: snap, tomorrowPlans: tomorrow.plans,
                                  dueTasks: try s.taskRows().map(\.task), insights: insights, log: log, enabled: enabled ?? all)
    }

    @Test func closeDayAndCaffeineCutoffFollowYourBedtime() throws {
        let now = at(9, 12)
        let s = try store(now: now)
        try s.logFood(name: "coffee", nutrition: Nutrition(kcal: 40, caffeineMg: 110), consumedAt: at(9, 10))
        let plan = NotificationPlanner().plan(try inputs(s, now: now))
        #expect(plan.map(\.kind) == [.caffeineCutoff, .closeDay])
        #expect(plan.first { $0.kind == .caffeineCutoff }?.fireAt == at(9, 18, 30))
        #expect(plan.first { $0.kind == .closeDay }?.fireAt == at(10, 0))
    }

    @Test func noCaffeineNoCutoffReminder() throws {
        let now = at(9, 12)
        let s = try store(now: now)
        #expect(NotificationPlanner().plan(try inputs(s, now: now)).map(\.kind) == [.closeDay])
    }

    @Test func capOfTwoUnrequestedCountsWhatWasAlreadySent() throws {
        let now = at(9, 12)
        let s = try store(now: now)
        try s.logFood(name: "coffee", nutrition: Nutrition(kcal: 40, caffeineMg: 110), consumedAt: at(9, 10))
        let insight = Insight(detectorID: "trend", detectorVersion: 1, subjectKey: "sleep", kind: .trend, title: "Bedtime moved",
                              explanation: [], effect: 2, confidence: .high, pValue: nil, domain: "sleep")
        #expect(NotificationPlanner().plan(try inputs(s, now: now, insights: [insight])).map(\.kind) == [.caffeineCutoff, .closeDay],
                "insight is third by priority and the cap is 2")
        let sent = NotificationLogEntry(id: UUID(), kind: "insight", requested: false, fireAt: at(9, 9), deliveredAt: at(9, 9), createdAt: at(9, 9))
        #expect(NotificationPlanner().plan(try inputs(s, now: now, log: [sent], insights: [insight])).map(\.kind) == [.closeDay],
                "one already sent today leaves room for one")
    }

    @Test func requestedOnesAreNotCappedAndCarryActions() throws {
        let now = at(9, 12)
        let s = try store(now: now)
        let p1 = try s.addPlanBlock(kind: .work, start: at(9, 14), end: at(9, 16), label: "deep work")
        try s.addPlanBlock(kind: .work, start: at(10, 10), end: at(10, 11))
        try s.addTask(NewTask(title: "pay rent", due: day.next))
        let plan = NotificationPlanner().plan(try inputs(s, now: now))
        let starts = plan.filter { $0.kind == .planStart }
        #expect(starts.count == 2 && starts.first?.title == "deep work starts now" && starts.first?.category == "plan-start")
        #expect(starts.first?.userInfo["planID"] == p1.id.uuidString)
        #expect(plan.contains { $0.kind == .taskDue && $0.fireAt == at(10, 9) && $0.title == "Due today: pay rent" })
    }

    @Test func runningTimerSuppressesPlanStartsAndSchedulesTheGuard() throws {
        let now = at(9, 12)
        let s = try store(now: now)
        try s.addPlanBlock(kind: .work, start: at(9, 14), end: at(9, 16))
        try s.startBlock(kind: .natureCall)
        let plan = NotificationPlanner().plan(try inputs(s, now: now))
        #expect(!plan.contains { $0.kind == .planStart })
        #expect(plan.first { $0.kind == .forgottenTimer }?.fireAt == at(9, 14))
    }

    @Test func sleepingMeansQuiet() throws {
        let now = at(9, 12)
        let s = try store(now: now)
        try s.startBlock(kind: .sleep)
        #expect(!NotificationPlanner().plan(try inputs(s, now: now)).contains { !$0.kind.isRequested })
    }

    @Test func ignoredThreeTimesBacksOffToEveryOtherDay() throws {
        let ignored = (1...3).map { k in
            NotificationLogEntry(id: UUID(), kind: "close-day", requested: false, fireAt: at(8 - k, 0), deliveredAt: at(8 - k, 0), createdAt: at(8 - k, 0))
        }
        // 9 Nov 2026 is an even day number since the epoch (runs); 10 Nov is odd (skipped).
        #expect(day.daysSinceEpoch % 2 == 0)
        for (d, expected) in [(9, true), (10, false)] {
            let now = at(d, 12)
            let s = try store(now: now)
            let target = LogicalDay(year: 2026, month: 11, day: d)!
            let snap = try s.snapshot(of: target, in: Self.tz)
            let x = NotificationInputs(now: now, timeZone: Self.tz, today: snap, tomorrowPlans: [], dueTasks: [],
                                       insights: [], log: ignored, enabled: all)
            #expect(NotificationPlanner().plan(x).contains { $0.kind == .closeDay } == expected, "day \(d)")
        }
        // Once you act on one, it's back to daily.
        var acted = ignored
        acted[0].actedAt = at(7, 0, 5)
        let now = at(10, 12)
        let s = try store(now: now)
        let x = NotificationInputs(now: now, timeZone: Self.tz, today: try s.snapshot(of: LogicalDay("2026-11-10")!, in: Self.tz),
                                   tomorrowPlans: [], dueTasks: [], insights: [], log: acted, enabled: all)
        #expect(NotificationPlanner().plan(x).contains { $0.kind == .closeDay })
    }

    @Test func switchesInSettingsAreRespected() throws {
        let now = at(9, 12)
        let s = try store(now: now)
        #expect(NotificationPlanner().plan(try inputs(s, now: now, enabled: [])).isEmpty)
    }

    @Test func stableIdentifiers() {
        let n = PlannedNotification(id: "close-day:2026-11-09", kind: .closeDay, fireAt: Date(), title: "", body: "", category: nil, userInfo: [:])
        #expect(n.logID == PlannedNotification(id: "close-day:2026-11-09", kind: .closeDay, fireAt: Date(), title: "x", body: "", category: nil, userInfo: [:]).logID)
    }
}
