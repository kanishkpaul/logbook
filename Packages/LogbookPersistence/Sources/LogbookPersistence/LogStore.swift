import Foundation
import GRDB
import LogbookCore
import SQLiteData

/// The write path for logged data.
///
/// Every write applies day attribution with the *current* `boundary` and
/// stores the result, so changing the boundary later never rewrites history.
/// Time, time zone and ids are injected, so tests are deterministic.
///
/// The `…Row` builders are pure: they apply the same rules without touching
/// the database, so a caller (the importer) can insert many rows in one
/// transaction.
public struct LogStore: Sendable {
    public let database: any DatabaseWriter
    public var boundary: DayBoundary
    public var now: @Sendable () -> Date
    public var timeZone: @Sendable () -> TimeZone
    public var uuid: @Sendable () -> UUID

    public init(
        database: any DatabaseWriter,
        boundary: DayBoundary = .standard,
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

    // MARK: Row builders (pure)

    /// A finished block with its logical day attributed.
    public func blockRow(
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
        return TimeBlock(
            id: id ?? uuid(), kind: kind, label: label, categoryID: categoryID,
            startUTC: start, endUTC: end, tzIdentifier: tz.identifier,
            logicalDay: Attribution.day(kind: kind, start: start, end: end, boundary: boundary, timeZone: tz),
            isEstimate: isEstimate, source: source, importBatchID: importBatchID, rawText: rawText,
            createdAt: t, updatedAt: t
        )
    }

    /// A food entry with nutrition snapshotted:
    /// explicit `nutrition` wins, else the library food × `servings`, else
    /// no values (*needs values*).
    public func foodEntryRow(
        name: String,
        food: Food? = nil,
        servings: Double = 1,
        quantity: Double? = nil,
        unit: String? = nil,
        nutrition: Nutrition? = nil,
        consumedAt: Date? = nil,
        timeZone tzOverride: TimeZone? = nil,
        isEstimate: Bool = false,
        source: Source = .manual,
        rawText: String? = nil,
        importBatchID: ImportBatch.ID? = nil,
        id: UUID? = nil
    ) -> FoodLogEntry {
        let t = now(), tz = tzOverride ?? timeZone()
        let at = consumedAt ?? t
        let snapshot = nutrition ?? food?.nutrition.scaled(by: servings) ?? Nutrition()
        var entry = FoodLogEntry(
            id: id ?? uuid(), foodID: food?.id, name: name, quantity: quantity, unit: unit,
            consumedAt: at, tzIdentifier: tz.identifier,
            logicalDay: boundary.logicalDay(containing: at, in: tz),
            isEstimate: isEstimate, source: source, importBatchID: importBatchID, rawText: rawText,
            createdAt: t, updatedAt: t
        )
        entry.nutrition = snapshot
        return entry
    }

    public func foodRow(
        name: String,
        nutrition: Nutrition,
        servingSize: Double? = nil,
        servingUnit: String? = nil,
        importBatchID: ImportBatch.ID? = nil,
        id: UUID? = nil
    ) -> Food {
        let t = now()
        var food = Food(
            id: id ?? uuid(), name: name, servingSize: servingSize, servingUnit: servingUnit,
            createdAt: t, updatedAt: t, importBatchID: importBatchID
        )
        food.nutrition = nutrition
        return food
    }

    public func metricSampleRow(
        metricID: MetricDefinition.ID,
        value: Double,
        day: LogicalDay? = nil,
        isEstimate: Bool = false,
        source: Source = .manual,
        rawText: String? = nil,
        importBatchID: ImportBatch.ID? = nil,
        id: UUID? = nil
    ) -> MetricSample {
        let t = now()
        return MetricSample(
            id: id ?? uuid(), metricID: metricID,
            logicalDay: day ?? boundary.logicalDay(containing: t, in: timeZone()),
            value: value, recordedAt: t, isEstimate: isEstimate, source: source,
            importBatchID: importBatchID, rawText: rawText, createdAt: t, updatedAt: t
        )
    }

    public func importBatchRow(sourceName: String, lineCount: Int, note: String = "") -> ImportBatch {
        ImportBatch(id: uuid(), sourceName: sourceName, note: note, lineCount: lineCount, importedAt: now())
    }

    // MARK: Time blocks

    /// Starts a timer: a block with no end, saved immediately.
    @discardableResult
    public func startBlock(
        kind: BlockKind,
        label: String = "",
        categoryID: Category.ID? = nil,
        taskID: TodoTask.ID? = nil,
        planBlockID: PlanBlock.ID? = nil
    ) throws -> TimeBlock {
        let t = now(), tz = timeZone()
        let block = TimeBlock(
            id: uuid(), kind: kind, label: label, categoryID: categoryID,
            startUTC: t, endUTC: nil, tzIdentifier: tz.identifier,
            logicalDay: Attribution.day(kind: kind, start: t, end: nil, boundary: boundary, timeZone: tz),
            source: .timer, createdAt: t, updatedAt: t, taskID: taskID, planBlockID: planBlockID
        )
        try database.write { db in
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
        return try database.write { db in
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

    /// Running blocks, at most one per kind (also enforced by a trigger).
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
        let block = try blockRow(
            kind: kind, start: start, end: end, label: label, categoryID: categoryID,
            timeZone: tzOverride, isEstimate: isEstimate, source: source, rawText: rawText,
            importBatchID: importBatchID, id: id
        )
        try database.write { db in try TimeBlock.insert { block }.execute(db) }
        return block
    }

    /// Changes a block's times; attribution is recomputed because the block itself changed.
    @discardableResult
    public func retime(id: TimeBlock.ID, start: Date, end: Date?) throws -> TimeBlock {
        if let end, end < start { throw Failure.endBeforeStart }
        let t = now()
        return try database.write { db in
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
        try database.write { db in
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
        let food = foodRow(name: name, nutrition: nutrition, servingSize: servingSize, servingUnit: servingUnit, id: id)
        try database.write { db in try Food.insert { food }.execute(db) }
        return food
    }

    /// Edits a library food. Past log entries keep their snapshotted values.
    @discardableResult
    public func updateFood(id: Food.ID, name: String? = nil, nutrition: Nutrition? = nil) throws -> Food {
        let t = now()
        return try database.write { db in
            guard var food = try Food.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            if let name { food.name = name }
            if let nutrition { food.nutrition = nutrition }
            food.updatedAt = t
            try Food.update(food).execute(db)
            return food
        }
    }

    /// Logs something eaten, copying nutrition onto the entry (see `foodEntryRow`).
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
        let entry = foodEntryRow(
            name: name, food: food, servings: servings, quantity: quantity, unit: unit,
            nutrition: nutrition, consumedAt: consumedAt, isEstimate: isEstimate, source: source,
            rawText: rawText, importBatchID: importBatchID, id: id
        )
        try database.write { db in try FoodLogEntry.insert { entry }.execute(db) }
        return entry
    }

    // MARK: Metrics

    /// The active definition for a metric key (`steps`, `active_kcal`, or a custom key).
    public static func metricDefinition(key: String, in db: Database) throws -> MetricDefinition? {
        try MetricDefinition.where { $0.key.eq(key) && $0.archivedAt.is(nil) }.fetchOne(db)
    }

    /// Records a value for a metric on a logical day.
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
        try database.write { db in
            guard let def = try Self.metricDefinition(key: key, in: db) else { throw Failure.unknownMetric(key) }
            let sample = metricSampleRow(
                metricID: def.id, value: value, day: day, isEstimate: isEstimate, source: source,
                rawText: rawText, importBatchID: importBatchID, id: id
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
}
