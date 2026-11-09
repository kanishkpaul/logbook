import Foundation
import LogbookCore
import LogbookPersistence
import Testing
@testable import LogbookImport

@Suite struct PlanShorthandTests {
    let today = LogicalDay("2026-11-09")! // Monday

    @Test func fullTask() {
        let t = PlanShorthand.task("write SIH deck ~45m !! fri #horizon", today: today)
        #expect(t.title == "write SIH deck")
        #expect(t.estimateMinutes == 45)
        #expect(t.priority == 2)
        #expect(t.due == LogicalDay("2026-11-13"))
        #expect(t.listName == "horizon")
        #expect(t.scheduled == nil && !t.someday && t.recurrence == nil)
    }

    @Test func datesAndScheduling() {
        #expect(PlanShorthand.task("call mom mon", today: today).due == today, "a weekday includes today")
        #expect(PlanShorthand.task("pay rent 1 dec", today: today).due == LogicalDay("2026-12-01"))
        #expect(PlanShorthand.task("pay rent 2026-12-01", today: today).due == LogicalDay("2026-12-01"))
        let s = PlanShorthand.task("read paper @tomorrow ~1h30m", today: today)
        #expect(s.scheduled == today.next && s.estimateMinutes == 90 && s.title == "read paper")
        #expect(PlanShorthand.task("learn piano @someday", today: today).someday)
    }

    @Test func recurrence() {
        #expect(PlanShorthand.task("standup every weekday", today: today).recurrence?.weekdays == [1, 2, 3, 4, 5])
        #expect(PlanShorthand.task("gym every mon,wed,fri", today: today).recurrence?.description == "FREQ=WEEKLY;BYDAY=MO,WE,FR")
        #expect(PlanShorthand.task("review every 2 weeks", today: today).recurrence?.description == "FREQ=WEEKLY;INTERVAL=2")
        let w = PlanShorthand.task("water plants after 3 days", today: today)
        #expect(w.recurrence?.description == "AFTER;FREQ=DAILY;INTERVAL=3" && w.title == "water plants")
    }

    @Test func wordsThatLookLikeOptionsStayInTheTitle() {
        let t = PlanShorthand.task("read about every rule", today: today)
        #expect(t.title == "read about every rule" && t.recurrence == nil)
    }

    @Test func planBlocks() throws {
        let p = try #require(PlanShorthand.plan("1400-1600 deep work", today: today))
        #expect(p.day == today && p.kind == .work && p.label == "deep work")
        #expect(p.start == WallTime(day: today, minutes: 840) && p.end == WallTime(day: today, minutes: 960))
        let t = try #require(PlanShorthand.plan("tomorrow gym 1800-1900", today: today))
        #expect(t.day == today.next && t.kind.rawValue == "gym")
        let sleep = try #require(PlanShorthand.plan("sleep 0100-0900", today: today))
        #expect(sleep.start.day == today.next, "the coming night")
        let late = try #require(PlanShorthand.plan("sleep 2330-0730", today: today))
        #expect(late.start.day == today && late.end.day == today.next)
        #expect(PlanShorthand.plan("deep work", today: today) == nil)
    }
}

@Suite struct QuickEntryPlanTests {
    static let tz = TimeZone(identifier: "Asia/Kolkata")!

    func make() throws -> QuickEntry {
        let now = Calendar.gregorian(in: Self.tz).date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
        return QuickEntry(store: LogStore(database: try AppDatabase.openInMemory(), now: { now }, timeZone: { Self.tz }))
    }

    @Test func addsATask() throws {
        let q = try make()
        let i = try q.interpret("t write SIH deck ~45m !! fri #horizon")
        #expect(i.lines == [.init(kind: "task", title: "write SIH deck", detail: "~45m · !! · due Fri 13 Nov · #horizon")])
        try q.commit(i)
        let row = try #require(try q.store.taskRows().first)
        #expect(row.task.estimateMin == 45 && row.listName == "horizon" && row.task.rawText == "t write SIH deck ~45m !! fri #horizon")
        #expect(try q.interpret("t standup every weekday").lines.first?.detail == "every weekday")
        #expect(try q.interpret("t ~45m").problem != nil)
    }

    @Test func plansABlock() throws {
        let q = try make()
        let i = try q.interpret("plan 1400-1600 deep work")
        #expect(i.lines == [.init(kind: "plan", title: "Plan work · deep work", detail: "today 14:00–16:00 · 2h")])
        try q.commit(i)
        let plans = try q.store.snapshot(of: LogicalDay("2026-11-09")!, in: Self.tz).plans
        #expect(plans.map(\.label) == ["deep work"] && plans.first?.status == .planned)
        #expect(try q.interpret("plan tomorrow gym 1800-1900").lines.first?.detail == "tomorrow 18:00–19:00 · 1h")
        #expect(try q.interpret("plan deep work").problem != nil)
    }
}
