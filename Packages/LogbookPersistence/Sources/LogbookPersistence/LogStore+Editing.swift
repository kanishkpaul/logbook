import Foundation
import GRDB
import LogbookCore
import SQLiteData

// Dictionary (the food library) and edits to logged entries.
extension LogStore {
    // MARK: Dictionary

    /// Dictionary entries, favourites first, then by name.
    public func dictionary(includeArchived: Bool = false) throws -> [Food] {
        try database.read { db in
            try Food
                .where { includeArchived || $0.archivedAt.is(nil) }
                .order { ($0.isFavourite.desc(), $0.name.collate(.nocase)) }
                .fetchAll(db)
        }
    }

    /// Inserts or updates a dictionary entry (bumping `updatedAt`).
    /// Past log entries keep their snapshotted values either way.
    @discardableResult
    public func saveFood(_ food: Food) throws -> Food {
        var food = food
        food.updatedAt = now()
        let row = food
        try database.write { db in
            if try Food.find(row.id).fetchCount(db) > 0 {
                try Food.update(row).execute(db)
            } else {
                try Food.insert { row }.execute(db)
            }
        }
        return row
    }

    /// Hides an entry from the dictionary and from name matching; history keeps it.
    public func archiveFood(id: Food.ID, archived: Bool = true) throws {
        let t = now()
        try database.write { db in
            guard var food = try Food.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            food.archivedAt = archived ? t : nil
            food.updatedAt = t
            try Food.update(food).execute(db)
        }
    }

    /// A new, unsaved dictionary entry with a fresh id.
    public func newFood(name: String = "") -> Food {
        foodRow(name: name, nutrition: Nutrition())
    }

    // MARK: Entries

    /// Fills in or corrects an entry's values (e.g. at Close the day).
    @discardableResult
    public func updateFoodEntry(id: FoodLogEntry.ID, nutrition: Nutrition, isEstimate: Bool) throws -> FoodLogEntry {
        let t = now()
        return try database.write { db in
            guard var entry = try FoodLogEntry.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            entry.nutrition = nutrition
            entry.isEstimate = isEstimate
            entry.updatedAt = t
            try FoodLogEntry.update(entry).execute(db)
            return entry
        }
    }

    public func deleteFoodEntry(id: FoodLogEntry.ID) throws {
        let t = now()
        try database.write { db in
            guard var entry = try FoodLogEntry.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            entry.deletedAt = t
            entry.updatedAt = t
            try FoodLogEntry.update(entry).execute(db)
        }
    }

    public func deleteSample(id: MetricSample.ID) throws {
        let t = now()
        try database.write { db in
            guard var sample = try MetricSample.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            sample.deletedAt = t
            sample.updatedAt = t
            try MetricSample.update(sample).execute(db)
        }
    }

    /// Stops a running block at a given instant (forgotten-timer guard: "stop at …").
    @discardableResult
    public func stopBlock(id: TimeBlock.ID, at end: Date) throws -> TimeBlock {
        let tz = timeZone()
        let t = now()
        return try database.write { db in
            guard var block = try TimeBlock.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            guard block.endUTC == nil else { throw Failure.notRunning(id) }
            guard end >= block.startUTC else { throw Failure.endBeforeStart }
            block.endUTC = end
            block.tzIdentifier = tz.identifier
            block.logicalDay = Attribution.day(kind: block.kind, start: block.startUTC, end: end, boundary: boundary, timeZone: tz)
            block.updatedAt = t
            try TimeBlock.update(block).execute(db)
            return block
        }
    }
}
