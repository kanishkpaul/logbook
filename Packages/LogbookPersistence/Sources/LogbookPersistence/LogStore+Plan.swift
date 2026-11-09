import Foundation
import GRDB
import LogbookCore
import SQLiteData

/// A task with its list name and the time actually spent on it.
public struct TaskRow: Hashable, Sendable, Identifiable {
    public var task: TodoTask
    public var listName: String?
    /// Minutes of finished time blocks linked to the task.
    public var actualMin: Int
    public var id: TodoTask.ID { task.id }
}

/// Fields for a new task (the shorthand parser lives in LogbookImport).
public struct NewTask: Sendable {
    public var title: String
    public var listName: String?
    public var priority: Int = 0
    public var due: LogicalDay?
    public var scheduled: LogicalDay?
    public var someday = false
    public var estimateMin: Int?
    public var recurrence: Recurrence?
    public var rawText: String?

    public init(title: String, listName: String? = nil, priority: Int = 0, due: LogicalDay? = nil, scheduled: LogicalDay? = nil,
                someday: Bool = false, estimateMin: Int? = nil, recurrence: Recurrence? = nil, rawText: String? = nil) {
        self.title = title
        self.listName = listName
        self.priority = priority
        self.due = due
        self.scheduled = scheduled
        self.someday = someday
        self.estimateMin = estimateMin
        self.recurrence = recurrence
        self.rawText = rawText
    }
}

extension LogStore {
    var today: LogicalDay { boundary.logicalDay(containing: now(), in: timeZone()) }

    // MARK: Lists

    /// The list called `name` (case-insensitive), created if needed.
    public func taskList(named name: String, in db: Database) throws -> TaskList {
        let lists = try TaskList.where { $0.archivedAt.is(nil) }.fetchAll(db)
        if let found = lists.first(where: { $0.name.lowercased() == name.lowercased() }) { return found }
        let t = now()
        let list = TaskList(id: uuid(), name: name, sort: lists.count, createdAt: t, updatedAt: t)
        try TaskList.insert { list }.execute(db)
        return list
    }

    public func taskLists() throws -> [TaskList] {
        try database.read { db in try TaskList.where { $0.archivedAt.is(nil) }.order(by: \.sort).fetchAll(db) }
    }

    // MARK: Tasks

    @discardableResult
    public func addTask(_ new: NewTask) throws -> TodoTask {
        let t = now()
        return try database.write { db in
            let list = try new.listName.map { try taskList(named: $0, in: db) }
            let task = TodoTask(
                id: uuid(), listID: list?.id, title: new.title, priority: new.priority,
                dueDay: new.due, scheduledDay: new.scheduled, isSomeday: new.someday,
                estimateMin: new.estimateMin, recurrenceRule: new.recurrence?.description,
                rawText: new.rawText, createdAt: t, updatedAt: t
            )
            try TodoTask.insert { task }.execute(db)
            return task
        }
    }

    /// Every task that isn't deleted, with list names and actual time.
    public func taskRows(includeDoneSince since: Date? = nil) throws -> [TaskRow] {
        try database.read { db in try Self.taskRows(db, doneSince: since) }
    }

    static func taskRows(_ db: Database, doneSince: Date?, ids: [UUID]? = nil) throws -> [TaskRow] {
        let all = try TodoTask.where { $0.deletedAt.is(nil) }.order(by: \.sort).fetchAll(db)
        let cutoff = doneSince ?? .distantFuture
        let tasks = all.filter { task in
            let keep = task.status == .open || (task.completedAt ?? .distantPast) >= cutoff
            return keep && (ids?.contains(task.id) ?? true)
        }
        let lists = Dictionary(uniqueKeysWithValues: try TaskList.all.fetchAll(db).map { ($0.id, $0.name) })
        let rows = try Row.fetchAll(db, sql: """
            SELECT task_id, CAST(round(SUM((julianday(end_utc) - julianday(start_utc)) * 1440)) AS INTEGER) AS minutes
            FROM time_block WHERE task_id IS NOT NULL AND end_utc IS NOT NULL AND deleted_at IS NULL
            GROUP BY task_id
            """)
        var actual: [String: Int] = [:]
        for r in rows { actual[(r["task_id"] as String).lowercased()] = r["minutes"] }
        return tasks.map { t in
            TaskRow(task: t, listName: t.listID.flatMap { lists[$0] }, actualMin: actual[t.id.uuidString.lowercased()] ?? 0)
        }
    }

    private func updateTask(_ id: TodoTask.ID, _ change: (inout TodoTask) -> Void) throws -> TodoTask {
        let t = now()
        return try database.write { db in
            guard var task = try TodoTask.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            change(&task)
            task.updatedAt = t
            try TodoTask.update(task).execute(db)
            return task
        }
    }

    /// Marks a task done. A repeating task gets its next instance, scheduled
    /// by its rule (or counted from today for "after done" rules).
    @discardableResult
    public func completeTask(id: TodoTask.ID) throws -> TodoTask? {
        let t = now(), day = today
        return try database.write { db in
            guard var task = try TodoTask.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            task.status = .done
            task.completedAt = t
            task.updatedAt = t
            try TodoTask.update(task).execute(db)
            guard let rule = task.recurrence else { return nil }
            // Completing late doesn't leave the next one in the past; early keeps the schedule.
            let anchor = task.scheduledDay ?? task.dueDay ?? day
            let next = rule.next(after: rule.afterCompletion ? day : max(anchor, day), anchor: anchor)
            let hasDue = task.dueDay != nil, hasScheduled = task.scheduledDay != nil
            let row = TodoTask(
                id: uuid(), listID: task.listID, title: task.title, notes: task.notes, priority: task.priority,
                dueDay: hasDue ? next : nil, scheduledDay: hasScheduled || !hasDue ? next : nil,
                estimateMin: task.estimateMin, recurrenceRule: task.recurrenceRule,
                sort: task.sort, rawText: task.rawText, createdAt: t, updatedAt: t
            )
            try TodoTask.insert { row }.execute(db)
            return row
        }
    }

    @discardableResult
    public func reopenTask(id: TodoTask.ID) throws -> TodoTask {
        try updateTask(id) { $0.status = .open; $0.completedAt = nil }
    }

    @discardableResult
    public func dropTask(id: TodoTask.ID) throws -> TodoTask {
        let t = now()
        return try updateTask(id) { $0.status = .dropped; $0.completedAt = t }
    }

    public func deleteTask(id: TodoTask.ID) throws {
        let t = now()
        _ = try updateTask(id) { $0.deletedAt = t }
    }

    /// Moves a task to a day (`nil` = no day), or to Someday.
    @discardableResult
    public func scheduleTask(id: TodoTask.ID, day: LogicalDay?, someday: Bool = false) throws -> TodoTask {
        try updateTask(id) {
            $0.scheduledDay = someday ? nil : day
            $0.isSomeday = someday
        }
    }

    @discardableResult
    public func setEstimate(id: TodoTask.ID, minutes: Int?) throws -> TodoTask {
        try updateTask(id) { $0.estimateMin = minutes }
    }

    /// Starts a work timer linked to the task (its time counts as the task's actual).
    @discardableResult
    public func startTask(id: TodoTask.ID) throws -> TimeBlock {
        let task = try database.read { db in try TodoTask.find(id).fetchOne(db) }
        guard let task else { throw Failure.notFound(id) }
        return try startBlock(kind: .work, label: task.title, taskID: task.id)
    }

    // MARK: Plan blocks

    @discardableResult
    public func addPlanBlock(
        kind: BlockKind, start: Date, end: Date, label: String = "", taskID: TodoTask.ID? = nil,
        templateID: PlanTemplate.ID? = nil, rawText: String? = nil
    ) throws -> PlanBlock {
        guard end >= start else { throw Failure.endBeforeStart }
        let t = now(), tz = timeZone()
        let plan = PlanBlock(
            id: uuid(), kind: kind, label: label, taskID: taskID, startUTC: start, endUTC: end,
            tzIdentifier: tz.identifier,
            logicalDay: Attribution.day(kind: kind, start: start, end: end, boundary: boundary, timeZone: tz),
            templateID: templateID, rawText: rawText, createdAt: t, updatedAt: t
        )
        try database.write { db in try PlanBlock.insert { plan }.execute(db) }
        return plan
    }

    @discardableResult
    public func setPlanStatus(id: PlanBlock.ID, _ status: PlanStatus) throws -> PlanBlock {
        let t = now()
        return try database.write { db in
            guard var plan = try PlanBlock.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            plan.status = status
            plan.updatedAt = t
            try PlanBlock.update(plan).execute(db)
            return plan
        }
    }

    public func deletePlanBlock(id: PlanBlock.ID) throws {
        let t = now()
        try database.write { db in
            guard var plan = try PlanBlock.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            plan.deletedAt = t
            plan.updatedAt = t
            try PlanBlock.update(plan).execute(db)
        }
    }

    /// "Done as planned": logs the planned block as what happened, in one step.
    @discardableResult
    public func completeAsPlanned(id: PlanBlock.ID) throws -> TimeBlock {
        let t = now()
        return try database.write { db in
            guard var plan = try PlanBlock.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            var block = try blockRow(kind: plan.kind, start: plan.startUTC, end: plan.endUTC, label: plan.label,
                                     timeZone: TimeZone(identifier: plan.tzIdentifier), source: .plan)
            block.taskID = plan.taskID
            block.planBlockID = plan.id
            let row = block
            try TimeBlock.insert { row }.execute(db)
            plan.status = .done
            plan.updatedAt = t
            try PlanBlock.update(plan).execute(db)
            return row
        }
    }

    /// Starts the planned block's timer now (linked to the plan and its task).
    @discardableResult
    public func startPlanned(id: PlanBlock.ID) throws -> TimeBlock {
        let plan = try database.read { db in try PlanBlock.find(id).fetchOne(db) }
        guard let plan else { throw Failure.notFound(id) }
        let block = try startBlock(kind: plan.kind, label: plan.label, taskID: plan.taskID, planBlockID: plan.id)
        try setPlanStatus(id: id, .started)
        return block
    }

    // MARK: Templates

    /// Saves `day`'s planned blocks as a reusable "ideal day".
    @discardableResult
    public func saveTemplate(name: String, from day: LogicalDay) throws -> PlanTemplate {
        let t = now(), tz = timeZone()
        let midnight = DayBoundary.calendarDay.start(of: day, in: tz)
        return try database.write { db in
            // By start time, not attribution: tonight's planned sleep belongs to this day's shape.
            let nextMidnight = DayBoundary.calendarDay.start(of: day.next, in: tz)
            let plans = try PlanBlock
                .where { $0.deletedAt.is(nil) && $0.startUTC >= midnight && $0.startUTC < nextMidnight }
                .order(by: \.startUTC)
                .fetchAll(db)
            var template = try PlanTemplate.where { $0.archivedAt.is(nil) }.fetchAll(db).first { $0.name.lowercased() == name.lowercased() }
                ?? PlanTemplate(id: uuid(), name: name, createdAt: t, updatedAt: t)
            template.blocks = plans.map {
                .init(kind: $0.kind.rawValue, label: $0.label,
                      startMinute: Int(($0.startUTC.timeIntervalSince(midnight) / 60).rounded()),
                      endMinute: Int(($0.endUTC.timeIntervalSince(midnight) / 60).rounded()))
            }
            template.updatedAt = t
            let row = template
            if try PlanTemplate.find(row.id).fetchCount(db) > 0 {
                try PlanTemplate.update(row).execute(db)
            } else {
                try PlanTemplate.insert { row }.execute(db)
            }
            return row
        }
    }

    public func templates() throws -> [PlanTemplate] {
        try database.read { db in try PlanTemplate.where { $0.archivedAt.is(nil) }.order { $0.name.collate(.nocase) }.fetchAll(db) }
    }

    /// Stamps a template onto `day`: ordinary plan blocks, linked to the template.
    @discardableResult
    public func stamp(templateID: PlanTemplate.ID, on day: LogicalDay) throws -> [PlanBlock] {
        let tz = timeZone()
        let template = try database.read { db in try PlanTemplate.find(templateID).fetchOne(db) }
        guard let template else { throw Failure.notFound(templateID) }
        let cal = Calendar.gregorian(in: tz)
        func at(_ minute: Int) -> Date {
            let d = day.adding(days: minute >= 0 ? minute / 1440 : -1)
            let m = ((minute % 1440) + 1440) % 1440
            return cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: m / 60, minute: m % 60))!
        }
        return try template.blocks.map {
            try addPlanBlock(kind: BlockKind(rawValue: $0.kind), start: at($0.startMinute), end: at($0.endMinute),
                             label: $0.label, templateID: template.id)
        }
    }
}

extension LogStore {
    /// Emits all tasks (open, plus done/dropped since `doneSince`) on every change.
    public func observeTasks(doneSince: Date) -> AsyncThrowingStream<[TaskRow], any Error> {
        let values = ValueObservation.tracking { db in
            try Self.taskRows(db, doneSince: doneSince)
        }.removeDuplicates().values(in: database)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await rows in values { continuation.yield(rows) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
