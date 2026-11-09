import Foundation
import GRDB
import LogbookCore
import SQLiteData
import Testing
@testable import LogbookPersistence

@Suite struct PlanTests {
    let env = TestEnv(start: Date(timeIntervalSince1970: 0))
    let day = LogicalDay("2026-11-09")!

    func store() throws -> LogStore {
        env.set(env.at(2026, 11, 9, 9, 0))
        return try env.store()
    }

    // MARK: Tasks

    @Test func addTaskCreatesItsListOnce() throws {
        let s = try store()
        let a = try s.addTask(NewTask(title: "deck", listName: "Horizon", priority: 2, due: day, estimateMin: 45))
        let b = try s.addTask(NewTask(title: "notes", listName: "horizon"))
        #expect(a.listID == b.listID)
        #expect(try s.taskLists().map(\.name) == ["Horizon"])
        let rows = try s.taskRows()
        #expect(rows.map(\.listName) == ["Horizon", "Horizon"])
    }

    @Test func startingATaskTracksItsActualTime() throws {
        let s = try store()
        let task = try s.addTask(NewTask(title: "write deck", scheduled: day, estimateMin: 45))
        let timer = try s.startTask(id: task.id)
        #expect(timer.taskID == task.id && timer.label == "write deck")
        env.advance(minutes: 50)
        try s.stopBlock(id: timer.id)
        #expect(try s.taskRows().first?.actualMin == 50)
    }

    @Test func completingARepeatingTaskSchedulesTheNextOne() throws {
        let s = try store()
        let daily = try s.addTask(NewTask(title: "journal", scheduled: day.adding(days: -3), recurrence: Recurrence(frequency: .daily)))
        let next = try #require(try s.completeTask(id: daily.id))
        #expect(next.scheduledDay == day.next, "completed late: the next one is after today, not in the past")
        #expect(next.status == .open && next.recurrenceRule == "FREQ=DAILY")

        let water = try s.addTask(NewTask(title: "water plants", due: day.adding(days: 5), recurrence: Recurrence(frequency: .daily, interval: 3, afterCompletion: true)))
        let n2 = try #require(try s.completeTask(id: water.id))
        #expect(n2.dueDay == day.adding(days: 3) && n2.scheduledDay == nil, "after-done counts from today and keeps due-only")

        let once = try s.addTask(NewTask(title: "once"))
        #expect(try s.completeTask(id: once.id) == nil)
    }

    @Test func scheduleSomedayDropAndReopen() throws {
        let s = try store()
        let t = try s.addTask(NewTask(title: "learn piano", scheduled: day))
        #expect(try s.scheduleTask(id: t.id, day: nil, someday: true).isSomeday)
        #expect(try s.scheduleTask(id: t.id, day: day.next).scheduledDay == day.next)
        #expect(try s.dropTask(id: t.id).status == .dropped)
        #expect(try s.reopenTask(id: t.id).status == .open)
    }

    @Test func todaysTasksInTheSnapshot() throws {
        let s = try store()
        try s.addTask(NewTask(title: "overdue", scheduled: day.previous))
        try s.addTask(NewTask(title: "due today", due: day))
        try s.addTask(NewTask(title: "tomorrow", scheduled: day.next))
        try s.addTask(NewTask(title: "someday", someday: true))
        try s.addTask(NewTask(title: "inbox"))
        let done = try s.addTask(NewTask(title: "done today", scheduled: day))
        try s.completeTask(id: done.id)
        let titles = try s.snapshot(of: day, in: env.tz).tasks.map(\.task.title)
        #expect(Set(titles) == ["overdue", "due today", "done today"])
    }

    // MARK: Plan blocks

    @Test func planAndRealityStaySeparateButLinked() throws {
        let s = try store()
        let plan = try s.addPlanBlock(kind: .work, start: env.at(2026, 11, 9, 14, 0), end: env.at(2026, 11, 9, 16, 0), label: "deep work")
        #expect(plan.logicalDay == day && plan.minutes == 120)
        let actual = try s.completeAsPlanned(id: plan.id)
        #expect(actual.planBlockID == plan.id && actual.source == .plan)
        #expect(actual.startUTC == plan.startUTC && actual.endUTC == plan.endUTC)
        let snap = try s.snapshot(of: day, in: env.tz)
        #expect(snap.plans.map(\.status) == [.done])
        #expect(snap.today.workMin == 120)
        let planCount = try s.database.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM plan_block")! }
        #expect(planCount == 1, "logging the plan doesn't turn it into a time block")
    }

    @Test func startingAPlannedBlockLinksTheTimer() throws {
        let s = try store()
        let task = try s.addTask(NewTask(title: "deck"))
        let plan = try s.addPlanBlock(kind: .work, start: env.at(2026, 11, 9, 9, 0), end: env.at(2026, 11, 9, 10, 0), label: "deck", taskID: task.id)
        let timer = try s.startPlanned(id: plan.id)
        #expect(timer.planBlockID == plan.id && timer.taskID == task.id)
        #expect(try s.snapshot(of: day, in: env.tz).plans.first?.status == .started)
    }

    @Test func templatesStampTheSameShapeOntoAnotherDay() throws {
        let s = try store()
        try s.addPlanBlock(kind: .work, start: env.at(2026, 11, 9, 10, 0), end: env.at(2026, 11, 9, 13, 0), label: "deep work")
        try s.addPlanBlock(kind: BlockKind(rawValue: "gym"), start: env.at(2026, 11, 9, 18, 0), end: env.at(2026, 11, 9, 19, 0), label: "gym")
        try s.addPlanBlock(kind: .sleep, start: env.at(2026, 11, 9, 23, 30), end: env.at(2026, 11, 10, 7, 30))
        let t = try s.saveTemplate(name: "Ideal day", from: day)
        #expect(t.blocks.map(\.startMinute) == [600, 1080, 1410])
        #expect(t.blocks.last?.endMinute == 1890, "sleep ends the next morning")

        let stamped = try s.stamp(templateID: t.id, on: LogicalDay("2026-11-12")!)
        #expect(stamped.map(\.startUTC) == [env.at(2026, 11, 12, 10, 0), env.at(2026, 11, 12, 18, 0), env.at(2026, 11, 12, 23, 30)])
        #expect(stamped.last?.endUTC == env.at(2026, 11, 13, 7, 30))
        #expect(stamped.allSatisfy { $0.templateID == t.id })
        #expect(try s.saveTemplate(name: "ideal DAY", from: day).id == t.id, "same name updates")
    }

    // MARK: Safety

    @Test func plansSurviveTheJSONRoundTrip() throws {
        let s = try store()
        let task = try s.addTask(NewTask(title: "deck", listName: "Horizon"))
        let plan = try s.addPlanBlock(kind: .work, start: env.at(2026, 11, 9, 14, 0), end: env.at(2026, 11, 9, 15, 0), taskID: task.id)
        try s.completeAsPlanned(id: plan.id)
        let data = try DataExport.json(s.database, exportedAt: Date(timeIntervalSince1970: 1))
        let fresh = try AppDatabase.openInMemory()
        try DataExport.restore(data, into: fresh)
        #expect(try DataExport.json(fresh, exportedAt: Date(timeIntervalSince1970: 1)) == data)
    }
}
