import Foundation
import GRDB
import LogbookCore
import SQLiteData

/// Everything the Today screen needs for one logical day, read in one go.
/// Raw rows only: presentation maths happens in Core, not here or in views.
public struct DaySnapshot: Sendable, Equatable {
    public var day: LogicalDay
    /// The day's window in the snapshot's time zone.
    public var window: DateInterval
    /// Blocks overlapping the window (including running ones), oldest first.
    public var blocks: [TimeBlock]
    /// Every running block, whatever its day (at most one per kind).
    public var running: [TimeBlock]
    /// Entries attributed to the day.
    public var foods: [FoodLogEntry]
    /// Metric samples attributed to the day, with their metric's key.
    public var samples: [DaySample]
    /// Entries with caffeine or nicotine consumed from 24 h before the window
    /// to its end, for the in-system models.
    public var doses: [FoodLogEntry]
    /// `daily_facts` for the 28 days before `day`, then `day` itself (gaps filled).
    public var history: [DailyFacts]
    /// Starts of finished sleep blocks in the 28 days up to the window's end.
    public var sleepStarts: [Date] = []

    public var today: DailyFacts { history.last ?? .empty(day) }
    /// The 28 days before today (for baselines).
    public var previous: [DailyFacts] { Array(history.dropLast()) }
}

public struct DaySample: Sendable, Hashable, Identifiable {
    public var sample: MetricSample
    public var key: String
    public var name: String
    public var unit: String
    public var id: MetricSample.ID { sample.id }
}

extension LogStore {
    public static let historyDays = 28

    /// Reads a snapshot of `day` in `timeZone`.
    public func snapshot(of day: LogicalDay, in timeZone: TimeZone) throws -> DaySnapshot {
        try database.read { db in try Self.snapshot(of: day, in: timeZone, boundary: boundary, db: db) }
    }

    /// Emits a fresh snapshot now and after every change to the database.
    public func observe(_ day: LogicalDay, in timeZone: TimeZone) -> AsyncThrowingStream<DaySnapshot, any Error> {
        let boundary = boundary
        let observation = ValueObservation.tracking { db in
            try Self.snapshot(of: day, in: timeZone, boundary: boundary, db: db)
        }.removeDuplicates()
        let values = observation.values(in: database)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await snapshot in values { continuation.yield(snapshot) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func snapshot(of day: LogicalDay, in timeZone: TimeZone, boundary: DayBoundary, db: Database) throws -> DaySnapshot {
        let window = boundary.interval(of: day, in: timeZone)
        let start = window.start, end = window.end
        let blocks = try TimeBlock
            .where { $0.deletedAt.is(nil) && $0.startUTC < end }
            .where { #sql("(\($0.endUTC) IS NULL OR \($0.endUTC) > \(start))", as: Bool.self) }
            .order(by: \.startUTC)
            .fetchAll(db)
        let running = try TimeBlock
            .where { $0.deletedAt.is(nil) && $0.endUTC.is(nil) }
            .order(by: \.startUTC)
            .fetchAll(db)
        let foods = try FoodLogEntry
            .where { $0.deletedAt.is(nil) && $0.logicalDay.eq(day) }
            .order(by: \.consumedAt)
            .fetchAll(db)
        let doseStart = start.addingTimeInterval(-24 * 3600)
        let doses = try FoodLogEntry
            .where { $0.deletedAt.is(nil) && $0.consumedAt >= doseStart && $0.consumedAt < end }
            .where { #sql("(coalesce(\($0.caffeineMg), 0) > 0 OR coalesce(\($0.nicotineMg), 0) > 0)", as: Bool.self) }
            .order(by: \.consumedAt)
            .fetchAll(db)
        let definitions = Dictionary(uniqueKeysWithValues: try MetricDefinition.all.fetchAll(db).map { ($0.id, $0) })
        let samples = try MetricSample
            .where { $0.deletedAt.is(nil) && $0.logicalDay.eq(day) }
            .order(by: \.recordedAt)
            .fetchAll(db)
            .map { s in
                let d = definitions[s.metricID]
                return DaySample(sample: s, key: d?.key ?? "?", name: d?.name ?? "?", unit: d?.unit ?? "")
            }
        let first = day.adding(days: -historyDays)
        let rows = try DailyFacts.where { $0.logicalDay >= first && $0.logicalDay <= day }.fetchAll(db)
        let byDay = Dictionary(rows.map { ($0.logicalDay, $0) }, uniquingKeysWith: { a, _ in a })
        let history = LogicalDay.range(first, through: day).map { byDay[$0] ?? .empty($0) }
        let sleepSince = start.addingTimeInterval(-Double(historyDays) * 86_400)
        let sleepStarts = try TimeBlock
            .where { $0.deletedAt.is(nil) && $0.kind.eq(BlockKind.sleep) && $0.startUTC >= sleepSince && $0.startUTC < end }
            .where { #sql("\($0.endUTC) IS NOT NULL", as: Bool.self) }
            .order(by: \.startUTC)
            .fetchAll(db)
            .map(\.startUTC)
        return DaySnapshot(day: day, window: window, blocks: blocks, running: running, foods: foods,
                           samples: samples, doses: doses, history: history, sleepStarts: sleepStarts)
    }
}
