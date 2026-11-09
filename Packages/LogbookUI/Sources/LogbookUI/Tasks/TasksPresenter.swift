import Foundation
import LogbookCore
import LogbookPersistence

/// Where a task shows up.
public enum TaskView: Hashable, Sendable {
    case inbox, today, upcoming, anytime, someday, done
    case list(String)

    public var title: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .anytime: "Anytime"
        case .someday: "Someday"
        case .done: "Done"
        case .list(let name): name
        }
    }

    public var symbol: String {
        switch self {
        case .inbox: "tray"
        case .today: "star"
        case .upcoming: "calendar"
        case .anytime: "square.stack"
        case .someday: "archivebox"
        case .done: "checkmark.circle"
        case .list: "list.bullet"
        }
    }
}

public struct TasksState: Equatable {
    public var counts: [TaskView: Int]
    public var lists: [String]
    public var sections: [Section]

    public struct Section: Equatable, Identifiable {
        public var title: String
        public var tasks: [PlanState.TaskItem]
        public var id: String { title }
    }
}

/// Smart views over tasks. Pure; dates come from `today`.
public struct TasksPresenter {
    public var timeZone: TimeZone

    public init(timeZone: TimeZone) {
        self.timeZone = timeZone
    }

    public static func belongs(_ row: TaskRow, to view: TaskView, today: LogicalDay) -> Bool {
        let t = row.task
        let open = t.status == .open && !t.isSomeday
        let dated = t.scheduledDay ?? t.dueDay
        let todayish = (t.scheduledDay.map { $0 <= today } ?? false) || (t.dueDay.map { $0 <= today } ?? false)
        switch view {
        case .inbox: return open && t.listID == nil && dated == nil
        case .today: return open && todayish
        case .upcoming: return open && !todayish && dated != nil
        case .anytime: return open && t.listID != nil && dated == nil
        case .someday: return t.status == .open && t.isSomeday
        case .done: return t.status != .open
        case .list(let name): return t.status == .open && row.listName?.lowercased() == name.lowercased()
        }
    }

    func dayText(_ d: LogicalDay, today: LogicalDay) -> String {
        if d == today { return "Today" }
        if d == today.next { return "Tomorrow" }
        if d < today { return "Earlier" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = timeZone
        f.dateFormat = today.days(to: d) < 7 ? "EEEE" : "EEE d MMM"
        return f.string(from: DayBoundary.calendarDay.start(of: d, in: timeZone).addingTimeInterval(43_200))
    }

    func item(_ row: TaskRow, today: LogicalDay) -> PlanState.TaskItem {
        let t = row.task
        var parts: [String] = []
        if let e = t.estimateMin { parts.append("~\(Durations.compact(minutes: e))") }
        if row.actualMin > 0 { parts.append("\(Durations.compact(minutes: row.actualMin)) spent") }
        if let d = t.dueDay { parts.append("due \(dayText(d, today: today).lowercased())") }
        if let l = row.listName { parts.append("#\(l)") }
        if let r = t.recurrence { parts.append(r.summary) }
        if let e = t.estimateMin, row.actualMin > 0, t.status == .done {
            parts.append(String(format: "%.1f× estimate", Double(row.actualMin) / Double(max(1, e))))
        }
        let overdue = t.status == .open && ((t.dueDay.map { $0 < today } ?? false) || (t.scheduledDay.map { $0 < today } ?? false))
        return .init(id: t.id, title: t.title, detail: parts.joined(separator: " · "), priority: t.priority,
                     isDone: t.status == .done, isOverdue: overdue)
    }

    public func present(_ rows: [TaskRow], view: TaskView, today: LogicalDay) -> TasksState {
        let all: [TaskView] = [.inbox, .today, .upcoming, .anytime, .someday]
        var counts: [TaskView: Int] = [:]
        for v in all { counts[v] = rows.filter { Self.belongs($0, to: v, today: today) }.count }
        let lists = Array(Set(rows.compactMap(\.listName))).sorted { $0.lowercased() < $1.lowercased() }
        for l in lists { counts[.list(l)] = rows.filter { Self.belongs($0, to: .list(l), today: today) }.count }

        let picked = rows.filter { Self.belongs($0, to: view, today: today) }
        var sections: [TasksState.Section]
        switch view {
        case .upcoming:
            let grouped = Dictionary(grouping: picked) { ($0.task.scheduledDay ?? $0.task.dueDay)! }
            sections = grouped.keys.sorted().map { d in
                .init(title: dayText(d, today: today), tasks: grouped[d]!.sorted(by: Self.order).map { item($0, today: today) })
            }
        case .done:
            let sorted = picked.sorted { ($0.task.completedAt ?? .distantPast) > ($1.task.completedAt ?? .distantPast) }
            sections = [.init(title: "Done", tasks: sorted.map { item($0, today: today) })]
        case .today:
            let overdue = picked.filter { item($0, today: today).isOverdue }.sorted(by: Self.order)
            let rest = picked.filter { !item($0, today: today).isOverdue }.sorted(by: Self.order)
            sections = [.init(title: "Earlier", tasks: overdue.map { item($0, today: today) }),
                        .init(title: "Today", tasks: rest.map { item($0, today: today) })].filter { !$0.tasks.isEmpty }
        default:
            sections = [.init(title: view.title, tasks: picked.sorted(by: Self.order).map { item($0, today: today) })]
        }
        return TasksState(counts: counts, lists: lists, sections: sections.filter { !$0.tasks.isEmpty })
    }

    /// Priority first, then your own order, then oldest first.
    static func order(_ a: TaskRow, _ b: TaskRow) -> Bool {
        (-a.task.priority, a.task.sort, a.task.createdAt) < (-b.task.priority, b.task.sort, b.task.createdAt)
    }
}
