import Foundation
import GRDB
import LogbookCore
import SQLiteData

/// A meal with its items resolved to dictionary entries.
public struct MealDetail: Hashable, Sendable, Identifiable {
    public var meal: Meal
    public var items: [Item]
    public var id: Meal.ID { meal.id }

    public struct Item: Hashable, Sendable {
        public var item: MealItem
        public var food: Food

        /// `paneer 200g`, `egg x2`, `coffee`.
        public var label: String {
            if let q = item.quantity, let u = item.unit {
                return u == "x" ? "\(food.name) x\(NutritionFormat.number(q))" : "\(food.name) \(NutritionFormat.number(q))\(u)"
            }
            return item.servings == 1 ? food.name : "\(food.name) x\(NutritionFormat.number(item.servings))"
        }

        public var nutrition: Nutrition { food.nutrition.scaled(by: item.servings) }
    }

    public var nutrition: Nutrition { items.reduce(Nutrition()) { $0 + $1.nutrition } }
}

/// What a meal item is made of, before saving.
public struct MealPart: Hashable, Sendable {
    public var food: Food
    public var servings: Double
    public var quantity: Double?
    public var unit: String?

    public init(food: Food, servings: Double, quantity: Double? = nil, unit: String? = nil) {
        self.food = food
        self.servings = servings
        self.quantity = quantity
        self.unit = unit
    }
}

extension LogStore {
    // MARK: Copy, favourites, recents

    /// Copies a day's food to another day at the same wall-clock times, with
    /// the same snapshotted values (it's a copy, not a re-lookup).
    @discardableResult
    public func copyFood(from source: LogicalDay, to target: LogicalDay) throws -> [FoodLogEntry] {
        let tz = timeZone()
        let cal = Calendar.gregorian(in: tz)
        let shift = source.days(to: target)
        return try database.write { db in
            let entries = try FoodLogEntry
                .where { $0.deletedAt.is(nil) && $0.logicalDay.eq(source) }
                .order(by: \.consumedAt)
                .fetchAll(db)
            let copies = entries.map { e in
                let wall = cal.dateComponents([.hour, .minute, .second], from: e.consumedAt)
                let day = LogicalDay.civil(containing: e.consumedAt, in: tz).adding(days: shift)
                let at = cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day,
                                                       hour: wall.hour, minute: wall.minute, second: wall.second)) ?? e.consumedAt
                return foodEntryRow(
                    name: e.name, quantity: e.quantity, unit: e.unit, nutrition: e.nutrition, consumedAt: at,
                    isEstimate: e.isEstimate, rawText: "copied from \(source)"
                ).withFoodID(e.foodID)
            }
            for c in copies { try FoodLogEntry.insert { c }.execute(db) }
            return copies
        }
    }

    public func foodCount(on day: LogicalDay) throws -> Int {
        try database.read { db in
            try FoodLogEntry.where { $0.deletedAt.is(nil) && $0.logicalDay.eq(day) }.fetchCount(db)
        }
    }

    /// Names to offer as one-click buttons: favourites first, then the most
    /// frequent recent names (dictionary name when linked), newest breaking ties.
    public func quickAddNames(days: Int = 14, limit: Int = 8) throws -> [String] {
        let since = now().addingTimeInterval(-Double(days) * 86_400)
        return try database.read { db in
            let favourites = try Food
                .where { $0.isFavourite && $0.archivedAt.is(nil) }
                .order { $0.name.collate(.nocase) }
                .fetchAll(db)
                .map(\.name)
            let recent = try String.fetchAll(db, sql: """
                SELECT coalesce(f.name, e.name) AS label
                FROM food_log_entry e LEFT JOIN food f ON f.id = e.food_id AND f.archived_at IS NULL
                WHERE e.deleted_at IS NULL AND e.consumed_at >= ?
                GROUP BY lower(label)
                ORDER BY count(*) DESC, max(e.consumed_at) DESC
                LIMIT ?
                """, arguments: [Self.sqlDate(since), limit * 2])
            var seen = Set<String>()
            return (favourites + recent).filter { seen.insert($0.lowercased()).inserted }.prefix(limit).map { $0 }
        }
    }

    /// StructuredQueries' text format for instants, for raw SQL comparisons.
    static func sqlDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: date)
    }

    // MARK: Meals

    /// Creates or replaces (by name, case-insensitive) a meal and its items.
    @discardableResult
    public func saveMeal(name: String, parts: [MealPart]) throws -> MealDetail {
        let t = now()
        return try database.write { db in
            let key = name.lowercased()
            var meal = try Meal.where { $0.archivedAt.is(nil) }.fetchAll(db).first { $0.name.lowercased() == key }
                ?? Meal(id: uuid(), name: name, createdAt: t, updatedAt: t)
            meal.name = name
            meal.updatedAt = t
            let row = meal
            if try Meal.find(row.id).fetchCount(db) > 0 {
                try Meal.update(row).execute(db)
                try MealItem.where { $0.mealID.eq(row.id) }.delete().execute(db)
            } else {
                try Meal.insert { row }.execute(db)
            }
            var items: [MealDetail.Item] = []
            for (i, p) in parts.enumerated() {
                let item = MealItem(id: uuid(), mealID: row.id, foodID: p.food.id, servings: p.servings, quantity: p.quantity, unit: p.unit, sort: i)
                try MealItem.insert { item }.execute(db)
                items.append(.init(item: item, food: p.food))
            }
            return MealDetail(meal: row, items: items)
        }
    }

    /// Active meals with their items, by name.
    public func meals() throws -> [MealDetail] {
        try database.read { db in try Self.meals(db) }
    }

    static func meals(_ db: Database) throws -> [MealDetail] {
        let meals = try Meal.where { $0.archivedAt.is(nil) }.order { $0.name.collate(.nocase) }.fetchAll(db)
        let foods = Dictionary(uniqueKeysWithValues: try Food.all.fetchAll(db).map { ($0.id, $0) })
        let items = try MealItem.order(by: \.sort).fetchAll(db)
        return meals.map { meal in
            MealDetail(meal: meal, items: items.filter { $0.mealID == meal.id }.compactMap { i in foods[i.foodID].map { .init(item: i, food: $0) } })
        }
    }

    public func archiveMeal(id: Meal.ID) throws {
        let t = now()
        try database.write { db in
            guard var meal = try Meal.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            meal.archivedAt = t
            meal.updatedAt = t
            try Meal.update(meal).execute(db)
        }
    }

    /// One food entry per item, `times` over (e.g. `breakfast x2`).
    public func mealEntryRows(_ meal: MealDetail, times: Double = 1, consumedAt: Date? = nil) -> [FoodLogEntry] {
        meal.items.map { i in
            foodEntryRow(
                name: i.label, food: i.food, servings: i.item.servings * times,
                quantity: i.item.quantity.map { $0 * times }, unit: i.item.unit,
                consumedAt: consumedAt, rawText: "meal: \(meal.meal.name)"
            )
        }
    }
}

extension FoodLogEntry {
    func withFoodID(_ id: Food.ID?) -> FoodLogEntry {
        var copy = self
        copy.foodID = id
        return copy
    }
}
