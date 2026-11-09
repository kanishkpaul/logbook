import Foundation
import GRDB
import LogbookCore
import SQLiteData

extension LogStore {
    // MARK: Context

    /// The last `days` days (ending today) as plain series for the detectors.
    public func insightContext(days: Int = 60) throws -> InsightContext {
        let tz = timeZone(), now = now()
        let today = boundary.logicalDay(containing: now, in: tz)
        let first = today.adding(days: -(days - 1))
        return try database.read { db in
            let r = try Self.range(first, through: today, in: tz, boundary: boundary, db: db)
            func series(_ f: (DailyFacts) -> Double?) -> [Double?] { r.facts.map(f) }
            let metrics: [String: [Double?]] = [
                "work": series { $0.workMin.map(Double.init) },
                "sleep": series { $0.sleepMin.map(Double.init) },
                "kcal": series(\.kcal), "protein": series(\.proteinG),
                "caffeine": series(\.caffeineMg), "nicotine": series(\.nicotineMg),
                "burn": series(\.burnKcal), "steps": series(\.steps),
            ]
            let caffeineRows = try FoodLogEntry
                .where { $0.deletedAt.is(nil) && $0.logicalDay >= first }
                .where { #sql("coalesce(\($0.caffeineMg), 0) > 0", as: Bool.self) }
                .fetchAll(db)
            let lastByDay = Dictionary(grouping: caffeineRows, by: \.logicalDay).mapValues { $0.map(\.consumedAt).max()! }
            let sleepStarts = r.blocks.filter { $0.kind == .sleep }.map(\.startUTC)

            // Planning facts.
            let drifts = try Row.fetchAll(db, sql: """
                SELECT (julianday(t.start_utc) - julianday(p.start_utc)) * 1440 AS drift
                FROM time_block t JOIN plan_block p ON p.id = t.plan_block_id
                WHERE t.deleted_at IS NULL AND p.deleted_at IS NULL AND t.logical_day >= ?
                ORDER BY t.start_utc DESC LIMIT 40
                """, arguments: [first.description]).map { $0["drift"] as Double }
            let rows = try Self.taskRows(db, doneSince: now.addingTimeInterval(-90 * 86_400))
            var ratios: [String: [Double]] = [:]
            for row in rows where row.task.status == .done {
                guard let e = row.task.estimateMin, e > 0, row.actualMin > 0, let list = row.listName else { continue }
                ratios[list, default: []].append(Double(row.actualMin) / Double(e))
            }
            let tomorrow = today.next
            let tomorrowTasks = rows.filter { r in
                r.task.status == .open && !r.task.isSomeday && (r.task.scheduledDay == tomorrow || (r.task.scheduledDay == nil && r.task.dueDay == tomorrow))
            }.compactMap(\.task.estimateMin).reduce(0, +)
            let tomorrowPlanned = try PlanBlock
                .where { $0.deletedAt.is(nil) && $0.logicalDay.eq(tomorrow) && $0.kind.eq(BlockKind.work) }
                .fetchAll(db)
                .filter { $0.status != .skipped }
                .reduce(0) { $0 + $1.minutes }

            return InsightContext(
                today: today, now: now, timeZone: tz, days: r.days, metrics: metrics,
                lastCaffeine: r.days.map { lastByDay[$0] }, anyLogged: r.facts.map { !$0.isEmpty },
                sleepStarts: sleepStarts,
                plan: PlanFacts(startDrifts: drifts, estimateRatios: ratios,
                                tomorrowTaskMinutes: tomorrowTasks, tomorrowPlannedWorkMinutes: tomorrowPlanned)
            )
        }
    }

    // MARK: Memory

    public func insightMemory() throws -> [InsightMemoryState] {
        try database.read { db in
            try InsightMemoryRecord.all.fetchAll(db).map {
                InsightMemoryState(detectorID: $0.detectorID, subjectKey: $0.subjectKey, lastShownAt: $0.lastShownAt,
                                   dismissedAt: $0.dismissedAt, dismissedEffect: $0.dismissedEffect,
                                   snoozedUntil: $0.snoozedUntil, feedback: $0.feedback)
            }
        }
    }

    private func updateMemory(_ insight: Insight, _ change: (inout InsightMemoryRecord) -> Void) throws {
        try database.write { db in
            let existing = try InsightMemoryRecord
                .where { $0.detectorID.eq(insight.detectorID) && $0.subjectKey.eq(insight.subjectKey) }
                .fetchOne(db)
            var record = existing ?? InsightMemoryRecord(id: uuid(), detectorID: insight.detectorID,
                                                         detectorVersion: insight.detectorVersion, subjectKey: insight.subjectKey)
            record.detectorVersion = insight.detectorVersion
            change(&record)
            let row = record
            if existing == nil {
                try InsightMemoryRecord.insert { row }.execute(db)
            } else {
                try InsightMemoryRecord.update(row).execute(db)
            }
        }
    }

    /// Records that cards were shown (once per day per card).
    public func markShown(_ insights: [Insight]) throws {
        let t = now()
        let memory = Dictionary(try insightMemory().map { ("\($0.detectorID):\($0.subjectKey)", $0) }, uniquingKeysWith: { a, _ in a })
        for i in insights {
            if let last = memory[i.id]?.lastShownAt, t.timeIntervalSince(last) < 20 * 3600 { continue }
            try updateMemory(i) { $0.lastShownAt = t; $0.timesShown += 1 }
        }
    }

    /// Hides a card for 14 days, unless its effect grows by half.
    public func dismiss(_ insight: Insight) throws {
        let t = now()
        try updateMemory(insight) {
            $0.dismissedAt = t
            $0.dismissedEffect = insight.effect
            $0.timesDismissed += 1
        }
    }

    public func snooze(_ insight: Insight, days: Int = 7) throws {
        let until = now().addingTimeInterval(Double(days) * 86_400)
        try updateMemory(insight) { $0.snoozedUntil = until }
    }

    /// "useful" or "wrong" (wrong hides it for 30 days and flags the data for a look).
    public func feedback(_ insight: Insight, _ value: String) throws {
        let t = now()
        try updateMemory(insight) { $0.feedback = value; if $0.lastShownAt == nil { $0.lastShownAt = t } }
    }

    // MARK: Notification log

    public func logNotification(id: UUID, kind: String, requested: Bool, fireAt: Date) throws {
        let t = now()
        let entry = NotificationLogEntry(id: id, kind: kind, requested: requested, fireAt: fireAt, createdAt: t)
        try database.write { db in
            if try NotificationLogEntry.find(id).fetchCount(db) == 0 { try NotificationLogEntry.insert { entry }.execute(db) }
        }
    }

    public func markNotification(id: UUID, delivered: Date? = nil, acted action: String? = nil) throws {
        let t = now()
        try database.write { db in
            guard var e = try NotificationLogEntry.find(id).fetchOne(db) else { return }
            if let delivered { e.deliveredAt = e.deliveredAt ?? delivered }
            if let action { e.actedAt = t; e.action = action; e.deliveredAt = e.deliveredAt ?? t }
            try NotificationLogEntry.update(e).execute(db)
        }
    }

    /// Recent notifications, newest first.
    public func notificationLog(since: Date) throws -> [NotificationLogEntry] {
        try database.read { db in
            try NotificationLogEntry.where { $0.fireAt >= since }.order { $0.fireAt.desc() }.fetchAll(db)
        }
    }

    /// Removes log rows for notifications that were scheduled but never fired
    /// (they were replaced by a newer schedule).
    public func forgetUnfiredNotifications(after: Date) throws {
        try database.write { db in
            try NotificationLogEntry.where { $0.fireAt > after && $0.deliveredAt.is(nil) }.delete().execute(db)
        }
    }
}
