import Foundation
import LogbookCore
import SQLiteData

// Row types for the tables in `Schema`. Column names are snake_case in SQL
// (readable with `sqlite3`) and camelCase in Swift.

extension BlockKind: @retroactive QueryBindable {}
extension Source: @retroactive QueryBindable {}
extension LogicalDay: @retroactive QueryBindable {}

@Table("import_batch")
public struct ImportBatch: Hashable, Identifiable, Sendable {
    public let id: UUID
    @Column("source_name") public var sourceName: String
    public var note: String = ""
    @Column("line_count") public var lineCount: Int = 0
    @Column("imported_at") public var importedAt: Date
    @Column("undone_at") public var undoneAt: Date?
}

@Table("category")
public struct Category: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    @Column("color_hex") public var colorHex: String?
    public var symbol: String?
    public var sort: Int = 0
    @Column("created_at") public var createdAt: Date
    @Column("updated_at") public var updatedAt: Date
    @Column("archived_at") public var archivedAt: Date?
}

/// Work, sleep, nature's call or a custom kind. `endUTC == nil` means running.
@Table("time_block")
public struct TimeBlock: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var kind: BlockKind
    public var label: String = ""
    @Column("category_id") public var categoryID: Category.ID?
    @Column("start_utc") public var startUTC: Date
    @Column("end_utc") public var endUTC: Date?
    @Column("tz_identifier") public var tzIdentifier: String
    @Column("logical_day") public var logicalDay: LogicalDay
    public var note: String = ""
    @Column("is_estimate") public var isEstimate: Bool = false
    public var source: Source = .manual
    @Column("import_batch_id") public var importBatchID: ImportBatch.ID?
    @Column("raw_text") public var rawText: String?
    @Column("created_at") public var createdAt: Date
    @Column("updated_at") public var updatedAt: Date
    @Column("deleted_at") public var deletedAt: Date?
    @Column("task_id") public var taskID: TodoTask.ID?
    @Column("plan_block_id") public var planBlockID: PlanBlock.ID?

    public var isRunning: Bool { endUTC == nil }
}

/// A library food. Nutrition is per serving. Editing it never changes history,
/// because log entries copy the values when they are written.
@Table("food")
public struct Food: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    /// JSON array of alternative names, e.g. `["cof"]`.
    public var aliases: String = "[]"
    @Column("serving_size") public var servingSize: Double?
    @Column("serving_unit") public var servingUnit: String?
    public var kcal: Double?
    @Column("protein_g") public var proteinG: Double?
    @Column("carbs_g") public var carbsG: Double?
    @Column("fat_g") public var fatG: Double?
    @Column("caffeine_mg") public var caffeineMg: Double?
    @Column("nicotine_mg") public var nicotineMg: Double?
    @Column("is_favourite") public var isFavourite: Bool = false
    @Column("created_at") public var createdAt: Date
    @Column("updated_at") public var updatedAt: Date
    @Column("archived_at") public var archivedAt: Date?
    @Column("import_batch_id") public var importBatchID: ImportBatch.ID?

    public var nutrition: Nutrition {
        get {
            Nutrition(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG, caffeineMg: caffeineMg, nicotineMg: nicotineMg)
        }
        set {
            kcal = newValue.kcal
            proteinG = newValue.proteinG
            carbsG = newValue.carbsG
            fatG = newValue.fatG
            caffeineMg = newValue.caffeineMg
            nicotineMg = newValue.nicotineMg
        }
    }
}

extension Food {
    /// `aliases` decoded from its JSON array (e.g. `["cof", "coffee"]`).
    public var aliasList: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(aliases.utf8))) ?? [] }
        set {
            let clean = newValue.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            aliases = (try? String(data: JSONEncoder().encode(clean), encoding: .utf8)) ?? "[]"
        }
    }
}

/// What was eaten, with nutrition **snapshotted** at log time.
/// All-nil nutrition means *needs values*, which is not zero.
@Table("food_log_entry")
public struct FoodLogEntry: Hashable, Identifiable, Sendable {
    public let id: UUID
    @Column("food_id") public var foodID: Food.ID?
    public var name: String
    public var quantity: Double?
    public var unit: String?
    public var kcal: Double?
    @Column("protein_g") public var proteinG: Double?
    @Column("carbs_g") public var carbsG: Double?
    @Column("fat_g") public var fatG: Double?
    @Column("caffeine_mg") public var caffeineMg: Double?
    @Column("nicotine_mg") public var nicotineMg: Double?
    @Column("consumed_at") public var consumedAt: Date
    @Column("tz_identifier") public var tzIdentifier: String
    @Column("logical_day") public var logicalDay: LogicalDay
    @Column("is_estimate") public var isEstimate: Bool = false
    public var source: Source = .manual
    @Column("import_batch_id") public var importBatchID: ImportBatch.ID?
    @Column("raw_text") public var rawText: String?
    @Column("created_at") public var createdAt: Date
    @Column("updated_at") public var updatedAt: Date
    @Column("deleted_at") public var deletedAt: Date?

    public var nutrition: Nutrition {
        get {
            Nutrition(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG, caffeineMg: caffeineMg, nicotineMg: nicotineMg)
        }
        set {
            kcal = newValue.kcal
            proteinG = newValue.proteinG
            carbsG = newValue.carbsG
            fatG = newValue.fatG
            caffeineMg = newValue.caffeineMg
            nicotineMg = newValue.nicotineMg
        }
    }

    public var needsValues: Bool { nutrition.isEmpty }
}

public enum MetricAggregation: String, Sendable, QueryBindable, CaseIterable {
    case sum, avg, max, last
}

@Table("metric_definition")
public struct MetricDefinition: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var key: String
    public var name: String
    public var unit: String = ""
    @Column("value_type") public var valueType: String = "decimal"
    public var aggregation: MetricAggregation = .sum
    @Column("is_builtin") public var isBuiltin: Bool = false
    @Column("created_at") public var createdAt: Date
    @Column("updated_at") public var updatedAt: Date
    @Column("archived_at") public var archivedAt: Date?
}

@Table("metric_sample")
public struct MetricSample: Hashable, Identifiable, Sendable {
    public let id: UUID
    @Column("metric_id") public var metricID: MetricDefinition.ID
    @Column("logical_day") public var logicalDay: LogicalDay
    public var value: Double
    @Column("recorded_at") public var recordedAt: Date
    @Column("is_estimate") public var isEstimate: Bool = false
    public var source: Source = .manual
    @Column("import_batch_id") public var importBatchID: ImportBatch.ID?
    @Column("raw_text") public var rawText: String?
    @Column("created_at") public var createdAt: Date
    @Column("updated_at") public var updatedAt: Date
    @Column("deleted_at") public var deletedAt: Date?
}

/// A named group of dictionary items, logged together.
@Table("meal")
public struct Meal: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var aliases: String = "[]"
    @Column("created_at") public var createdAt: Date
    @Column("updated_at") public var updatedAt: Date
    @Column("archived_at") public var archivedAt: Date?

    public var aliasList: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(aliases.utf8))) ?? []
    }
}

@Table("meal_item")
public struct MealItem: Hashable, Identifiable, Sendable {
    public let id: UUID
    @Column("meal_id") public var mealID: Meal.ID
    @Column("food_id") public var foodID: Food.ID
    public var servings: Double = 1
    public var quantity: Double?
    public var unit: String?
    public var sort: Int = 0
}

@Table("task_list")
public struct TaskList: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    @Column("color_hex") public var colorHex: String?
    public var symbol: String?
    @Column("category_id") public var categoryID: Category.ID?
    public var sort: Int = 0
    @Column("created_at") public var createdAt: Date
    @Column("updated_at") public var updatedAt: Date
    @Column("archived_at") public var archivedAt: Date?
}

public enum TaskStatus: String, Sendable, QueryBindable, CaseIterable {
    case open, done, dropped
}

/// A to-do. (Named `TodoTask` to keep clear of Swift's `Task`.)
@Table("task")
public struct TodoTask: Hashable, Identifiable, Sendable {
    public let id: UUID
    @Column("list_id") public var listID: TaskList.ID?
    @Column("parent_task_id") public var parentTaskID: TodoTask.ID?
    public var title: String
    public var notes: String = ""
    /// 0 none, 1 `!`, 2 `!!`.
    public var priority: Int = 0
    @Column("due_day") public var dueDay: LogicalDay?
    @Column("scheduled_day") public var scheduledDay: LogicalDay?
    @Column("is_someday") public var isSomeday: Bool = false
    @Column("estimate_min") public var estimateMin: Int?
    @Column("recurrence_rule") public var recurrenceRule: String?
    public var status: TaskStatus = .open
    @Column("completed_at") public var completedAt: Date?
    public var sort: Int = 0
    public var source: Source = .manual
    @Column("raw_text") public var rawText: String?
    @Column("created_at") public var createdAt: Date
    @Column("updated_at") public var updatedAt: Date
    @Column("deleted_at") public var deletedAt: Date?

    public var recurrence: Recurrence? { recurrenceRule.flatMap { Recurrence(rule: $0) } }
}

public enum PlanStatus: String, Sendable, QueryBindable, CaseIterable {
    case planned, started, done, skipped
}

/// A block you planned. Never merged with `TimeBlock` (what happened).
@Table("plan_block")
public struct PlanBlock: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var kind: BlockKind
    public var label: String = ""
    @Column("category_id") public var categoryID: Category.ID?
    @Column("task_id") public var taskID: TodoTask.ID?
    @Column("start_utc") public var startUTC: Date
    @Column("end_utc") public var endUTC: Date
    @Column("tz_identifier") public var tzIdentifier: String
    @Column("logical_day") public var logicalDay: LogicalDay
    public var note: String = ""
    public var status: PlanStatus = .planned
    @Column("template_id") public var templateID: PlanTemplate.ID?
    @Column("recurrence_rule") public var recurrenceRule: String?
    public var source: Source = .manual
    @Column("raw_text") public var rawText: String?
    @Column("created_at") public var createdAt: Date
    @Column("updated_at") public var updatedAt: Date
    @Column("deleted_at") public var deletedAt: Date?

    public var minutes: Int { Durations.minutes(from: startUTC, to: endUTC) }
}

/// A saved "ideal day": blocks as minutes from midnight (end may pass 1440).
@Table("plan_template")
public struct PlanTemplate: Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var scope: String = "day"
    @Column("blocks_json") public var blocksJSON: String = "[]"
    @Column("created_at") public var createdAt: Date
    @Column("updated_at") public var updatedAt: Date
    @Column("archived_at") public var archivedAt: Date?

    public struct Block: Codable, Hashable, Sendable {
        public var kind: String
        public var label: String
        public var startMinute: Int
        public var endMinute: Int
    }

    public var blocks: [Block] {
        get { (try? JSONDecoder().decode([Block].self, from: Data(blocksJSON.utf8))) ?? [] }
        set { blocksJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }
}

@Table("change_log")
public struct ChangeLogEntry: Hashable, Identifiable, Sendable {
    public let id: UUID
    @Column("table_name") public var tableName: String
    @Column("row_id") public var rowID: String
    public var action: String
    @Column("before_json") public var beforeJSON: String?
    @Column("after_json") public var afterJSON: String?
    @Column("changed_at") public var changedAt: Date
}

/// One row of the `daily_facts` view. Every value is `nil` when nothing of
/// that kind was logged that day ("not logged" is not zero).
@Table("daily_facts")
public struct DailyFacts: Hashable, Sendable {
    @Column("logical_day") public var logicalDay: LogicalDay
    @Column("work_min") public var workMin: Int?
    @Column("work_blocks") public var workBlocks: Int?
    @Column("sleep_min") public var sleepMin: Int?
    @Column("nc_count") public var ncCount: Int?
    @Column("nc_min") public var ncMin: Int?
    public var kcal: Double?
    @Column("protein_g") public var proteinG: Double?
    @Column("carbs_g") public var carbsG: Double?
    @Column("fat_g") public var fatG: Double?
    @Column("caffeine_mg") public var caffeineMg: Double?
    @Column("nicotine_mg") public var nicotineMg: Double?
    @Column("food_entries") public var foodEntries: Int?
    @Column("food_needing_values") public var foodNeedingValues: Int?
    @Column("burn_kcal") public var burnKcal: Double?
    public var steps: Double?
    @Column("net_kcal") public var netKcal: Double?
    @Column("has_estimate") public var hasEstimate: Bool

    /// A day with nothing logged at all (used to fill gaps in a range).
    public static func empty(_ day: LogicalDay) -> DailyFacts {
        DailyFacts(
            logicalDay: day, workMin: nil, workBlocks: nil, sleepMin: nil, ncCount: nil, ncMin: nil,
            kcal: nil, proteinG: nil, carbsG: nil, fatG: nil, caffeineMg: nil, nicotineMg: nil,
            foodEntries: nil, foodNeedingValues: nil,
            burnKcal: nil, steps: nil, netKcal: nil, hasEstimate: false
        )
    }

    /// True when the day has no logged data (a gap, not a zero day).
    public var isEmpty: Bool { self == .empty(logicalDay) }
}
