import Foundation
import GRDB
import LogbookCore
import LogbookPersistence
import SQLiteData

/// Parse → plan (preview) → apply (one transaction) → undo (whole batch).
public struct Importer: Sendable {
    public let store: LogStore
    public var timeZone: TimeZone
    public var defaultYear: Int

    public init(store: LogStore, timeZone: TimeZone, defaultYear: Int) {
        self.store = store
        self.timeZone = timeZone
        self.defaultYear = defaultYear
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case batchNotFound(UUID)
        case alreadyUndone(UUID)

        public var description: String {
            switch self {
            case .batchNotFound(let id): "no import batch \(id.uuidString.lowercased())"
            case .alreadyUndone(let id): "import batch \(id.uuidString.lowercased()) was already undone"
            }
        }
    }

    /// The preview: what `apply` would write, with every issue. Writes nothing.
    public func preview(_ text: String, sourceName: String) throws -> ImportPlan {
        let doc = ShorthandParser(defaultYear: defaultYear).parse(text)
        return try ImportPlanner(store: store, timeZone: timeZone).plan(doc, sourceName: sourceName)
    }

    /// Writes a plan in one transaction under its `import_batch`. Rows that
    /// appeared since the preview (same id) are skipped, so this is idempotent.
    @discardableResult
    public func apply(_ plan: ImportPlan) throws -> ImportBatch {
        try store.database.write { db in
            try ImportBatch.insert { plan.batch }.execute(db)
            for food in plan.newFoods where try Food.find(food.id).fetchCount(db) == 0 {
                try Food.insert { food }.execute(db)
            }
            for row in plan.blocks where try TimeBlock.find(row.id).fetchCount(db) == 0 {
                try TimeBlock.insert { row }.execute(db)
            }
            for row in plan.foodEntries where try FoodLogEntry.find(row.id).fetchCount(db) == 0 {
                try FoodLogEntry.insert { row }.execute(db)
            }
            for row in plan.samples where try MetricSample.find(row.id).fetchCount(db) == 0 {
                try MetricSample.insert { row }.execute(db)
            }
        }
        return plan.batch
    }

    /// Removes every row the batch wrote (and library foods it created that
    /// nothing else uses). The batch row stays, marked undone; the change log
    /// keeps a copy of everything removed.
    public func undo(batchID: ImportBatch.ID) throws {
        let t = store.now()
        try store.database.write { db in
            guard var batch = try ImportBatch.find(batchID).fetchOne(db) else { throw Failure.batchNotFound(batchID) }
            guard batch.undoneAt == nil else { throw Failure.alreadyUndone(batchID) }
            try TimeBlock.where { $0.importBatchID.eq(batchID) }.delete().execute(db)
            try FoodLogEntry.where { $0.importBatchID.eq(batchID) }.delete().execute(db)
            try MetricSample.where { $0.importBatchID.eq(batchID) }.delete().execute(db)
            try db.execute(
                sql: """
                    DELETE FROM "food" WHERE "import_batch_id" = ?
                      AND "id" NOT IN (SELECT "food_id" FROM "food_log_entry" WHERE "food_id" IS NOT NULL)
                    """,
                arguments: [batchID.uuidString.lowercased()]
            )
            batch.undoneAt = t
            try ImportBatch.update(batch).execute(db)
        }
    }

    /// All batches, newest first.
    public func batches() throws -> [ImportBatch] {
        try store.database.read { db in
            try ImportBatch.order { $0.importedAt.desc() }.fetchAll(db)
        }
    }
}
