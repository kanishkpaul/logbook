import Foundation
import GRDB
import LogbookCore
import SQLiteData

/// The write path for logged data.
///
/// Every write applies day attribution with the *current* `boundary` and
/// stores the result, so changing the boundary later never rewrites history.
/// Time, time zone and ids are injected, so tests are deterministic.
public struct LogStore: Sendable {
    public let database: any DatabaseWriter
    public var boundary: DayBoundary
    public var now: @Sendable () -> Date
    public var timeZone: @Sendable () -> TimeZone
    public var uuid: @Sendable () -> UUID

    public init(
        database: any DatabaseWriter,
        boundary: DayBoundary,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
        uuid: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.database = database
        self.boundary = boundary
        self.now = now
        self.timeZone = timeZone
        self.uuid = uuid
    }

    public enum Failure: Error, Equatable {
        case alreadyRunning(BlockKind)
        case notFound(UUID)
        case notRunning(UUID)
        case endBeforeStart
        case unknownMetric(String)
    }

    // MARK: Time blocks

    /// Starts a timer: a block with no end, saved immediately.
    @discardableResult
    public func startBlock(kind: BlockKind, label: String = "", categoryID: Category.ID? = nil) throws -> TimeBlock {
        let t = now(), tz = timeZone()
        let block = TimeBlock(
            id: uuid(), kind: kind, label: label, categoryID: categoryID,
            startUTC: t, endUTC: nil, tzIdentifier: tz.identifier,
            logicalDay: Attribution.day(kind: kind, start: t, end: nil, boundary: boundary, timeZone: tz),
            source: .timer, createdAt: t, updatedAt: t
        )
        try write { db in
            if try !TimeBlock.where({ $0.kind.eq(kind) && $0.endUTC.is(nil) && $0.deletedAt.is(nil) }).fetchAll(db).isEmpty {
                throw Failure.alreadyRunning(kind)
            }
            try TimeBlock.insert { block }.execute(db)
        }
        return block
    }

    /// Stops a running block now and re-attributes it (sleep moves to the wake day).
    @discardableResult
    public func stopBlock(id: TimeBlock.ID) throws -> TimeBlock {
        let t = now(), tz = timeZone()
        return try write { db in
            guard var block = try TimeBlock.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            guard block.endUTC == nil else { throw Failure.notRunning(id) }
            block.endUTC = max(t, block.startUTC)
            block.tzIdentifier = tz.identifier
            block.logicalDay = Attribution.day(kind: block.kind, start: block.startUTC, end: block.endUTC, boundary: boundary, timeZone: tz)
            block.updatedAt = t
            try TimeBlock.update(block).execute(db)
            return block
        }
    }

    /// Running blocks, at most one per kind.
    public func runningBlocks() throws -> [TimeBlock] {
        try database.read { db in
            try TimeBlock.where { $0.endUTC.is(nil) && $0.deletedAt.is(nil) }.order(by: \.startUTC).fetchAll(db)
        }
    }

    /// Adds a finished block retroactively (the common case: most logging is after the fact).
    @discardableResult
    public func addBlock(
        kind: BlockKind,
        start: Date,
        end: Date,
        label: String = "",
        categoryID: Category.ID? = nil,
        timeZone tzOverride: TimeZone? = nil,
        isEstimate: Bool = false,
        source: Source = .manual,
        rawText: String? = nil,
        importBatchID: ImportBatch.ID? = nil,
        id: UUID? = nil
    ) throws -> TimeBlock {
        guard end >= start else { throw Failure.endBeforeStart }
        let t = now(), tz = tzOverride ?? timeZone()
        let block = TimeBlock(
            id: id ?? uuid(), kind: kind, label: label, categoryID: categoryID,
            startUTC: start, endUTC: end, tzIdentifier: tz.identifier,
            logicalDay: Attribution.day(kind: kind, start: start, end: end, boundary: boundary, timeZone: tz),
            isEstimate: isEstimate, source: source, importBatchID: importBatchID, rawText: rawText,
            createdAt: t, updatedAt: t
        )
        try write { db in try TimeBlock.insert { block }.execute(db) }
        return block
    }

    /// Changes a block's times; attribution is recomputed because the block itself changed.
    @discardableResult
    public func retime(id: TimeBlock.ID, start: Date, end: Date?) throws -> TimeBlock {
        if let end, end < start { throw Failure.endBeforeStart }
        let t = now()
        return try write { db in
            guard var block = try TimeBlock.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            let tz = TimeZone(identifier: block.tzIdentifier) ?? timeZone()
            block.startUTC = start
            block.endUTC = end
            block.logicalDay = Attribution.day(kind: block.kind, start: start, end: end, boundary: boundary, timeZone: tz)
            block.updatedAt = t
            try TimeBlock.update(block).execute(db)
            return block
        }
    }

    /// Soft delete: the row stays (and stays in the change log) but drops out of every total.
    public func deleteBlock(id: TimeBlock.ID) throws {
        let t = now()
        try write { db in
            guard var block = try TimeBlock.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            block.deletedAt = t
            block.updatedAt = t
            try TimeBlock.update(block).execute(db)
        }
    }

    // MARK: Food

    @discardableResult
    public func addFood(
        name: String,
        nutrition: Nutrition,
        servingSize: Double? = nil,
        servingUnit: String? = nil,
        id: UUID? = nil
    ) throws -> Food {
        let t = now()
        let food = Food(
            id: id ?? uuid(), name: name, servingSize: servingSize, servingUnit: servingUnit,
            kcal: nutrition.kcal, proteinG: nutrition.proteinG, caffeineMg: nutrition.caffeineMg,
            createdAt: t, updatedAt: t
        )
        try write { db in try Food.insert { food }.execute(db) }
        return food
    }

    /// Edits a library food. Past log entries keep their snapshotted values.
    @discardableResult
    public func updateFood(id: Food.ID, name: String? = nil, nutrition: Nutrition? = nil) throws -> Food {
        let t = now()
        return try write { db in
            guard var food = try Food.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            if let name { food.name = name }
            if let nutrition {
                food.kcal = nutrition.kcal
                food.proteinG = nutrition.proteinG
                food.caffeineMg = nutrition.caffeineMg
            }
            food.updatedAt = t
            try Food.update(food).execute(db)
            return food
        }
    }

    /// Logs something eaten, copying nutrition onto the entry.
    ///
    /// - `nutrition` given explicitly (e.g. `pulao 250g - 408 / 8 / 0`) wins.
    /// - Otherwise the library food's per-serving values × `servings`.
    /// - Otherwise the entry has no values and is flagged *needs values*.
    @discardableResult
    public func logFood(
        name: String,
        food: Food? = nil,
        servings: Double = 1,
        quantity: Double? = nil,
        unit: String? = nil,
        nutrition: Nutrition? = nil,
        consumedAt: Date? = nil,
        isEstimate: Bool = false,
        source: Source = .manual,
        rawText: String? = nil,
        importBatchID: ImportBatch.ID? = nil,
        id: UUID? = nil
    ) throws -> FoodLogEntry {
        let t = now(), tz = timeZone()
        let at = consumedAt ?? t
        let snapshot = nutrition ?? food?.nutrition.scaled(by: servings) ?? Nutrition()
        let entry = FoodLogEntry(
            id: id ?? uuid(), foodID: food?.id, name: name, quantity: quantity, unit: unit,
            kcal: snapshot.kcal, proteinG: snapshot.proteinG, caffeineMg: snapshot.caffeineMg,
            consumedAt: at, tzIdentifier: tz.identifier,
            logicalDay: boundary.logicalDay(containing: at, in: tz),
            isEstimate: isEstimate, source: source, importBatchID: importBatchID, rawText: rawText,
            createdAt: t, updatedAt: t
        )
        try write { db in try FoodLogEntry.insert { entry }.execute(db) }
        return entry
    }

    // MARK: Metrics

    /// Records a value for a metric (`steps`, `active_kcal`, or a custom key) on a logical day.
    @discardableResult
    public func recordMetric(
        key: String,
        value: Double,
        day: LogicalDay? = nil,
        isEstimate: Bool = false,
        source: Source = .manual,
        rawText: String? = nil,
        importBatchID: ImportBatch.ID? = nil,
        id: UUID? = nil
    ) throws -> MetricSample {
        let t = now(), tz = timeZone()
        return try write { db in
            guard let def = try MetricDefinition.where({ $0.key.eq(key) && $0.archivedAt.is(nil) }).fetchOne(db) else {
                throw Failure.unknownMetric(key)
            }
            let sample = MetricSample(
                id: id ?? uuid(), metricID: def.id,
                logicalDay: day ?? boundary.logicalDay(containing: t, in: tz),
                value: value, recordedAt: t, isEstimate: isEstimate, source: source,
                importBatchID: importBatchID, rawText: rawText, createdAt: t, updatedAt: t
            )
            try MetricSample.insert { sample }.execute(db)
            return sample
        }
    }

    // MARK: Reading

    /// `daily_facts` for every day in `start...end`, with explicit empty rows
    /// for days that have nothing logged (gaps, never zeros).
    public func dailyFacts(from start: LogicalDay, through end: LogicalDay) throws -> [DailyFacts] {
        let rows = try database.read { db in
            try DailyFacts
                .where { $0.logicalDay >= start && $0.logicalDay <= end }
                .fetchAll(db)
        }
        let byDay = Dictionary(rows.map { ($0.logicalDay, $0) }, uniquingKeysWith: { a, _ in a })
        return LogicalDay.range(start, through: end).map { byDay[$0] ?? .empty($0) }
    }

    // MARK: Helpers

    /// The one-running-per-kind rule is checked here first (for a typed error)
    /// and again by a database trigger (the backstop for any other writer).
    private func write<T>(_ body: (Database) throws -> T) throws -> T {
        try database.write(body)
    }
}
