import Foundation
import GRDB
import LogbookCore
import SQLiteData

/// Everything history screens need for a range of days: one `daily_facts` row
/// per day (gaps filled with empty rows) and the finished blocks overlapping
/// the range (for calendars, sleep windows and work by label).
public struct RangeSnapshot: Sendable, Equatable {
    public var first: LogicalDay
    public var last: LogicalDay
    public var window: DateInterval
    public var facts: [DailyFacts]
    public var blocks: [TimeBlock]
    /// Planned blocks overlapping the range.
    public var plans: [PlanBlock] = []
    /// Your custom metrics (active ones) and their per-day values.
    public var customDefinitions: [MetricDefinition] = []
    public var custom: [String: [LogicalDay: Double]] = [:]

    public var days: [LogicalDay] { facts.map(\.logicalDay) }
}

extension LogStore {
    public func range(_ first: LogicalDay, through last: LogicalDay, in timeZone: TimeZone) throws -> RangeSnapshot {
        try database.read { db in try Self.range(first, through: last, in: timeZone, boundary: boundary, db: db) }
    }

    /// Emits the range now and after every change to the database.
    public func observeRange(_ first: LogicalDay, through last: LogicalDay, in timeZone: TimeZone) -> AsyncThrowingStream<RangeSnapshot, any Error> {
        let boundary = boundary
        let values = ValueObservation.tracking { db in
            try Self.range(first, through: last, in: timeZone, boundary: boundary, db: db)
        }.removeDuplicates().values(in: database)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await r in values { continuation.yield(r) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func range(_ first: LogicalDay, through last: LogicalDay, in timeZone: TimeZone, boundary: DayBoundary, db: Database) throws -> RangeSnapshot {
        let window = DateInterval(start: boundary.start(of: first, in: timeZone), end: boundary.start(of: last.next, in: timeZone))
        let start = window.start, end = window.end
        let rows = try DailyFacts.where { $0.logicalDay >= first && $0.logicalDay <= last }.fetchAll(db)
        let byDay = Dictionary(rows.map { ($0.logicalDay, $0) }, uniquingKeysWith: { a, _ in a })
        let blocks = try TimeBlock
            .where { $0.deletedAt.is(nil) && $0.startUTC < end }
            .where { #sql("(\($0.endUTC) IS NOT NULL AND \($0.endUTC) > \(start))", as: Bool.self) }
            .order(by: \.startUTC)
            .fetchAll(db)
        let plans = try PlanBlock
            .where { $0.deletedAt.is(nil) && $0.startUTC < end && $0.endUTC > start }
            .order(by: \.startUTC)
            .fetchAll(db)
        let definitions = try MetricDefinition.where { !$0.isBuiltin && $0.archivedAt.is(nil) }.order { $0.name.collate(.nocase) }.fetchAll(db)
        return RangeSnapshot(first: first, last: last, window: window,
                             facts: LogicalDay.range(first, through: last).map { byDay[$0] ?? .empty($0) },
                             blocks: blocks, plans: plans, customDefinitions: definitions,
                             custom: try customValues(db, first: first, last: last))
    }
}
