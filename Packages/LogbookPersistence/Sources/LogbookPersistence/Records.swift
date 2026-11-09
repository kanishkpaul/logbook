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
    @Column("caffeine_mg") public var caffeineMg: Double?
    @Column("is_favourite") public var isFavourite: Bool = false
    @Column("created_at") public var createdAt: Date
    @Column("updated_at") public var updatedAt: Date
    @Column("archived_at") public var archivedAt: Date?
    @Column("import_batch_id") public var importBatchID: ImportBatch.ID?

    public var nutrition: Nutrition {
        Nutrition(kcal: kcal, proteinG: proteinG, caffeineMg: caffeineMg)
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
    @Column("caffeine_mg") public var caffeineMg: Double?
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
        Nutrition(kcal: kcal, proteinG: proteinG, caffeineMg: caffeineMg)
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
    @Column("caffeine_mg") public var caffeineMg: Double?
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
            kcal: nil, proteinG: nil, caffeineMg: nil, foodEntries: nil, foodNeedingValues: nil,
            burnKcal: nil, steps: nil, netKcal: nil, hasEstimate: false
        )
    }

    /// True when the day has no logged data (a gap, not a zero day).
    public var isEmpty: Bool { self == .empty(logicalDay) }
}
