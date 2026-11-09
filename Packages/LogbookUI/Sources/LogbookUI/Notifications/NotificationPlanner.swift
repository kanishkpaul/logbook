import CryptoKit
import Foundation
import LogbookCore
import LogbookPersistence

/// The kinds of local notification, each with its own switch in Settings.
public enum NotificationKind: String, CaseIterable, Sendable, Identifiable {
    case forgottenTimer = "forgotten-timer"
    case closeDay = "close-day"
    case caffeineCutoff = "caffeine-cutoff"
    case planStart = "plan-start"
    case taskDue = "task-due"
    case weeklyReview = "weekly-review"
    case insight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .forgottenTimer: "Forgotten timer"
        case .closeDay: "Close the day"
        case .caffeineCutoff: "Caffeine cutoff"
        case .planStart: "Planned block starting"
        case .taskDue: "Task due"
        case .weeklyReview: "Weekly review"
        case .insight: "Insight of the day"
        }
    }

    /// Asked for by you (a plan, a due date, a running timer): not capped.
    public var isRequested: Bool { [.forgottenTimer, .planStart, .taskDue].contains(self) }

    /// Order among unrequested ones when the daily cap bites.
    var priority: Int {
        switch self {
        case .closeDay: 0
        case .caffeineCutoff: 1
        case .insight: 2
        case .weeklyReview: 3
        default: 9
        }
    }
}

public struct PlannedNotification: Hashable, Sendable, Identifiable {
    /// Stable identifier, e.g. "plan-start:<uuid>", so rescheduling replaces.
    public var id: String
    public var kind: NotificationKind
    public var fireAt: Date
    public var title: String
    public var body: String
    /// Notification category for actions ("plan-start" → Start / Skip, "forgotten-timer" → Stop).
    public var category: String?
    public var userInfo: [String: String]

    /// A UUID derived from `id` (for the notification log).
    public var logID: UUID {
        var b = Array(SHA256.hash(data: Data(id.utf8)).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

/// Inputs for planning, already read from the database.
public struct NotificationInputs: Sendable {
    public var now: Date
    public var timeZone: TimeZone
    public var today: DaySnapshot
    public var tomorrowPlans: [PlanBlock]
    /// Open tasks due today or tomorrow.
    public var dueTasks: [TodoTask]
    public var insights: [Insight]
    public var log: [NotificationLogEntry]
    public var enabled: Set<NotificationKind>

    public init(now: Date, timeZone: TimeZone, today: DaySnapshot, tomorrowPlans: [PlanBlock], dueTasks: [TodoTask],
                insights: [Insight], log: [NotificationLogEntry], enabled: Set<NotificationKind>) {
        self.now = now
        self.timeZone = timeZone
        self.today = today
        self.tomorrowPlans = tomorrowPlans
        self.dueTasks = dueTasks
        self.insights = insights
        self.log = log
        self.enabled = enabled
    }
}

/// Decides which notifications should be pending for the next ~24 hours.
/// Pure: same inputs, same plan. Caps and quiet rules (master plan §10b):
/// - at most 2 unrequested notifications per day (requested ones are free);
/// - never during a running sleep block or your usual sleep window;
/// - a kind ignored 3 times in a row drops to every other day.
public struct NotificationPlanner {
    public static let dailyCap = 2

    public init() {}

    public func plan(_ x: NotificationInputs) -> [PlannedNotification] {
        let tz = x.timeZone
        let s = x.today
        let horizon = x.now.addingTimeInterval(24 * 3600)
        let clock = { (d: Date) -> String in
            let c = Calendar.gregorian(in: tz).dateComponents([.hour, .minute], from: d)
            return String(format: "%02d:%02d", c.hour!, c.minute!)
        }
        let onset = SleepTiming.usualOnset(s.sleepStarts, in: tz, minimum: 5)
        let bedtime = onset.map { SleepTiming.bedtime(endingDay: s.day, onset: $0, in: tz) }
        let sleepRunning = s.running.contains { $0.kind == .sleep }
        var out: [PlannedNotification] = []

        // Requested: forgotten timers.
        if x.enabled.contains(.forgottenTimer) {
            for b in s.running {
                let at = b.startUTC.addingTimeInterval(TodayPresenter.forgottenAfter(b.kind))
                guard at > x.now else { continue }
                let what = b.label.isEmpty ? (Domain(kind: b.kind)?.title ?? b.kind.rawValue) : b.label
                out.append(.init(id: "forgotten-timer:\(b.id)", kind: .forgottenTimer, fireAt: at,
                                 title: "\(what) is still running", body: "Started at \(clock(b.startUTC)). Still going?",
                                 category: "forgotten-timer", userInfo: ["blockID": b.id.uuidString]))
            }
        }

        // Requested: planned blocks starting (only if no timer is running then; re-planned on every change).
        if x.enabled.contains(.planStart), s.running.isEmpty {
            for p in (s.plans + x.tomorrowPlans) where p.status == .planned && p.startUTC > x.now && p.startUTC < horizon && p.kind != .sleep {
                let what = p.label.isEmpty ? (Domain(kind: p.kind)?.title ?? p.kind.rawValue) : p.label
                out.append(.init(id: "plan-start:\(p.id)", kind: .planStart, fireAt: p.startUTC,
                                 title: "\(what) starts now", body: "\(clock(p.startUTC))–\(clock(p.endUTC))",
                                 category: "plan-start", userInfo: ["planID": p.id.uuidString]))
            }
        }

        // Requested: tasks due (09:00 on the due day, unless a plan block is already linked).
        if x.enabled.contains(.taskDue) {
            let linked = Set((s.plans + x.tomorrowPlans).compactMap(\.taskID))
            for t in x.dueTasks where t.status == .open && !linked.contains(t.id) {
                guard let due = t.dueDay else { continue }
                let at = DayBoundary.calendarDay.start(of: due, in: tz).addingTimeInterval(9 * 3600)
                guard at > x.now, at < horizon else { continue }
                out.append(.init(id: "task-due:\(t.id):\(due)", kind: .taskDue, fireAt: at,
                                 title: "Due today: \(t.title)", body: t.estimateMin.map { "About \(Durations.compact(minutes: $0))" } ?? "",
                                 category: nil, userInfo: ["taskID": t.id.uuidString]))
            }
        }

        // Unrequested candidates.
        var extra: [PlannedNotification] = []
        if x.enabled.contains(.closeDay), let bedtime {
            let at = bedtime.addingTimeInterval(-3600)
            if at > x.now, at < horizon {
                extra.append(.init(id: "close-day:\(s.day)", kind: .closeDay, fireAt: at, title: "Close the day",
                                   body: "A minute to fill gaps and plan tomorrow.", category: nil, userInfo: [:]))
            }
        }
        if x.enabled.contains(.caffeineCutoff), let bedtime {
            let cutoff = bedtime.addingTimeInterval(-6 * 3600)
            let at = cutoff.addingTimeInterval(-30 * 60)
            let hadCaffeine = s.doses.contains { ($0.caffeineMg ?? 0) > 0 && s.window.contains($0.consumedAt) }
            if hadCaffeine, at > x.now, at < horizon {
                extra.append(.init(id: "caffeine-cutoff:\(s.day)", kind: .caffeineCutoff, fireAt: at,
                                   title: "Caffeine cutoff in 30 minutes",
                                   body: "\(clock(cutoff)) is 6 hours before your usual sleep time.", category: nil, userInfo: [:]))
            }
        }
        if x.enabled.contains(.insight), let top = x.insights.first(where: { $0.confidence != .low }) {
            let evening = DayBoundary.calendarDay.start(of: s.day, in: tz).addingTimeInterval(18 * 3600)
            let at = max(evening, x.now.addingTimeInterval(60))
            if at < horizon {
                extra.append(.init(id: "insight:\(top.id):\(s.day)", kind: .insight, fireAt: at, title: "Noticed",
                                   body: top.title, category: nil, userInfo: [:]))
            }
        }
        if x.enabled.contains(.weeklyReview), s.day.isoWeekday == 7 {
            let at = DayBoundary.calendarDay.start(of: s.day, in: tz).addingTimeInterval(18 * 3600)
            if at > x.now {
                extra.append(.init(id: "weekly-review:\(s.day)", kind: .weeklyReview, fireAt: at, title: "Your week in review",
                                   body: "Open Logbook for this week against the last.", category: nil, userInfo: [:]))
            }
        }

        // Quiet: never during a running sleep block or the usual sleep window (onset → +8h).
        if sleepRunning { extra.removeAll() }
        if let bedtime {
            let quiet = DateInterval(start: bedtime, duration: 8 * 3600)
            let earlier = DateInterval(start: bedtime.addingTimeInterval(-86_400), duration: 8 * 3600)
            extra.removeAll { quiet.contains($0.fireAt) || earlier.contains($0.fireAt) }
        }

        // Back off: a kind ignored 3 times in a row only runs on even days.
        extra.removeAll { n in
            let recent = x.log.filter { $0.kind == n.kind.rawValue && $0.deliveredAt != nil }.sorted { $0.fireAt > $1.fireAt }.prefix(3)
            return recent.count == 3 && recent.allSatisfy { $0.actedAt == nil } && s.day.daysSinceEpoch % 2 != 0
        }

        // Cap: unrequested ones already sent today count against the 2.
        let dayWindow = s.window
        let sentToday = x.log.filter { !$0.requested && $0.deliveredAt != nil && dayWindow.contains($0.fireAt) }.count
        let room = max(0, Self.dailyCap - sentToday)
        extra.sort { ($0.kind.priority, $0.fireAt) < ($1.kind.priority, $1.fireAt) }
        out += extra.prefix(room)

        return out.sorted { $0.fireAt < $1.fireAt }
    }
}
