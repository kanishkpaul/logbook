import Foundation
import LogbookCore
import LogbookPersistence
import Testing
@testable import LogbookUI

@Suite struct PlanPresenterTests {
    nonisolated static let tz = TimeZone(identifier: "Asia/Kolkata")!
    let cal = Calendar.gregorian(in: PlanPresenterTests.tz)
    let day = LogicalDay("2026-11-09")!

    func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    func store(at now: Date) throws -> LogStore {
        LogStore(database: try AppDatabase.openInMemory(), now: { now }, timeZone: { Self.tz })
    }

    func present(_ s: LogStore, now: Date) throws -> TodayState {
        TodayPresenter(timeZone: Self.tz).present(try s.snapshot(of: day, in: Self.tz), now: now)
    }

    @Test func plannedVersusDoneIsNeutralOverlap() throws {
        let now = at(9, 15)
        let s = try store(at: now)
        // Planned 10–13 and 14–16; did 10:30–12:30 and 14:00–now (15:00).
        try s.addPlanBlock(kind: .work, start: at(9, 10), end: at(9, 13), label: "deep work")
        try s.addPlanBlock(kind: .work, start: at(9, 14), end: at(9, 16), label: "email")
        try s.addBlock(kind: .work, start: at(9, 10, 30), end: at(9, 12, 30))
        try s.addBlock(kind: .work, start: at(9, 14), end: at(9, 15))
        let p = try present(s, now: now).plan
        #expect(p.summary == "Planned 5h of work · 3h of the 4h planned so far happened as planned")
        #expect(p.ghosts.count == 2)
        #expect(p.upNext?.title == "email" && p.upNext?.isNow == true)
    }

    @Test func driftFromLinkedBlocks() throws {
        let s = try store(at: at(9, 10, 20))
        let plan = try s.addPlanBlock(kind: .work, start: at(9, 10), end: at(9, 12))
        try s.startPlanned(id: plan.id) // started 20 minutes late
        let p = try present(s, now: at(9, 10, 30)).plan
        #expect(p.summary?.contains("started 20m later than planned") == true)
        #expect(p.upNext == nil, "the started block isn't 'up next' any more")
    }

    @Test func skippedPlansDropOutAndPastOnesAreReviewed() throws {
        let now = at(9, 20)
        let s = try store(at: now)
        let a = try s.addPlanBlock(kind: .work, start: at(9, 9), end: at(9, 10))
        try s.addPlanBlock(kind: .work, start: at(9, 11), end: at(9, 12))
        try s.setPlanStatus(id: a.id, .skipped)
        let state = try present(s, now: now)
        #expect(state.plan.ghosts.count == 1)
        #expect(state.closeDay.unreviewedPlans.count == 1)
    }

    @Test func todaysTasksAndCloseTheDay() throws {
        let s = try store(at: at(9, 20))
        try s.addTask(NewTask(title: "low", scheduled: day))
        try s.addTask(NewTask(title: "urgent", priority: 2, due: day, estimateMin: 45))
        try s.addTask(NewTask(title: "late", scheduled: day.adding(days: -2)))
        let done = try s.addTask(NewTask(title: "finished", scheduled: day))
        try s.completeTask(id: done.id)
        let state = try present(s, now: at(9, 20))
        #expect(state.plan.tasks.map(\.title) == ["urgent", "low", "late", "finished"])
        #expect(state.plan.tasks[0].detail == "~45m · due today")
        #expect(state.plan.tasks[2].isOverdue && state.plan.tasks[2].detail == "from Sat 7 Nov")
        #expect(state.closeDay.unfinishedTasks.map(\.title) == ["urgent", "low", "late"])
    }
}

@Suite struct TasksPresenterTests {
    nonisolated static let tz = TimeZone(identifier: "Asia/Kolkata")!
    let today = LogicalDay("2026-11-09")!

    @Test func smartViews() throws {
        let now = Calendar.gregorian(in: Self.tz).date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
        let s = LogStore(database: try AppDatabase.openInMemory(), now: { now }, timeZone: { Self.tz })
        try s.addTask(NewTask(title: "inbox thing"))
        try s.addTask(NewTask(title: "today thing", scheduled: today))
        try s.addTask(NewTask(title: "overdue", due: today.previous))
        try s.addTask(NewTask(title: "friday", due: LogicalDay("2026-11-13")))
        try s.addTask(NewTask(title: "next month", scheduled: LogicalDay("2026-12-01")))
        try s.addTask(NewTask(title: "anytime", listName: "Horizon"))
        try s.addTask(NewTask(title: "dream", someday: true))
        let d = try s.addTask(NewTask(title: "done one", listName: "Horizon", estimateMin: 30))
        let timer = try s.startTask(id: d.id)
        try s.stopBlock(id: timer.id, at: now.addingTimeInterval(45 * 60))
        try s.completeTask(id: d.id)

        let rows = try s.taskRows(includeDoneSince: now.addingTimeInterval(-86_400))
        let p = TasksPresenter(timeZone: Self.tz)
        let st = p.present(rows, view: .upcoming, today: today)
        #expect(st.counts[.inbox] == 1 && st.counts[.today] == 2 && st.counts[.upcoming] == 2)
        #expect(st.counts[.anytime] == 1 && st.counts[.someday] == 1 && st.counts[.list("Horizon")] == 1)
        #expect(st.sections.map(\.title) == ["Friday", "Tue 1 Dec"])

        let todayView = p.present(rows, view: .today, today: today)
        #expect(todayView.sections.map(\.title) == ["Earlier", "Today"])
        let done = p.present(rows, view: .done, today: today)
        #expect(done.sections.first?.tasks.first?.detail == "~30m · 45m spent · #Horizon · 1.5× estimate")
    }
}
