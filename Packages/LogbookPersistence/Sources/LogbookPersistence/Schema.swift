import Foundation
import GRDB

/// The database schema as append-only, named migrations.
///
/// Rules (CLAUDE.md):
/// - UUID primary keys stored as lowercase TEXT; no UNIQUE constraint other
///   than the primary key (keeps CloudKit sync possible later).
/// - Instants are UTC TEXT `yyyy-MM-dd HH:mm:ss.SSS` (StructuredQueries' Date
///   format), so `julianday()` works on them and `sqlite3` can read them.
/// - `logical_day` is `yyyy-MM-dd`, fixed when the row is written.
/// - Every logged row keeps provenance: `source`, `raw_text`, `import_batch_id`,
///   `is_estimate`, `created_at`, `updated_at`, `deleted_at` (soft delete).
/// - Never edit a migration once it has shipped; add a new one.
public enum Schema {
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1: logging tables", migrate: v1)
        migrator.registerMigration("v1: daily_facts views", migrate: v1Views)
        migrator.registerMigration("v1: change log triggers", migrate: v1ChangeLog)
        migrator.registerMigration("v2: food import batch", migrate: v2FoodImportBatch)
        migrator.registerMigration("v3: macros and nicotine", migrate: v3MacrosAndNicotine)
        migrator.registerMigration("v4: meals", migrate: v4Meals)
        return migrator
    }

    /// Fixed ids for built-in metric definitions.
    public enum BuiltinMetric {
        public static let steps = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        public static let activeKcal = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    }

    // MARK: v1

    static func v1(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE "import_batch" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "source_name" TEXT NOT NULL,
              "note" TEXT NOT NULL DEFAULT '',
              "line_count" INTEGER NOT NULL DEFAULT 0,
              "imported_at" TEXT NOT NULL,
              "undone_at" TEXT
            ) STRICT;

            CREATE TABLE "category" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "name" TEXT NOT NULL,
              "color_hex" TEXT,
              "symbol" TEXT,
              "sort" INTEGER NOT NULL DEFAULT 0,
              "created_at" TEXT NOT NULL,
              "updated_at" TEXT NOT NULL,
              "archived_at" TEXT
            ) STRICT;

            CREATE TABLE "time_block" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "kind" TEXT NOT NULL,
              "label" TEXT NOT NULL DEFAULT '',
              "category_id" TEXT REFERENCES "category"("id") ON DELETE SET NULL,
              "start_utc" TEXT NOT NULL,
              "end_utc" TEXT,
              "tz_identifier" TEXT NOT NULL,
              "logical_day" TEXT NOT NULL,
              "note" TEXT NOT NULL DEFAULT '',
              "is_estimate" INTEGER NOT NULL DEFAULT 0,
              "source" TEXT NOT NULL DEFAULT 'manual',
              "import_batch_id" TEXT REFERENCES "import_batch"("id") ON DELETE CASCADE,
              "raw_text" TEXT,
              "created_at" TEXT NOT NULL,
              "updated_at" TEXT NOT NULL,
              "deleted_at" TEXT,
              CHECK ("end_utc" IS NULL OR julianday("end_utc") >= julianday("start_utc"))
            ) STRICT;
            CREATE INDEX "time_block_logical_day" ON "time_block"("logical_day");
            CREATE INDEX "time_block_running" ON "time_block"("kind") WHERE "end_utc" IS NULL;

            CREATE TABLE "food" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "name" TEXT NOT NULL,
              "aliases" TEXT NOT NULL DEFAULT '[]',
              "serving_size" REAL,
              "serving_unit" TEXT,
              "kcal" REAL,
              "protein_g" REAL,
              "caffeine_mg" REAL,
              "is_favourite" INTEGER NOT NULL DEFAULT 0,
              "created_at" TEXT NOT NULL,
              "updated_at" TEXT NOT NULL,
              "archived_at" TEXT
            ) STRICT;

            CREATE TABLE "food_log_entry" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "food_id" TEXT REFERENCES "food"("id") ON DELETE SET NULL,
              "name" TEXT NOT NULL,
              "quantity" REAL,
              "unit" TEXT,
              "kcal" REAL,
              "protein_g" REAL,
              "caffeine_mg" REAL,
              "consumed_at" TEXT NOT NULL,
              "tz_identifier" TEXT NOT NULL,
              "logical_day" TEXT NOT NULL,
              "is_estimate" INTEGER NOT NULL DEFAULT 0,
              "source" TEXT NOT NULL DEFAULT 'manual',
              "import_batch_id" TEXT REFERENCES "import_batch"("id") ON DELETE CASCADE,
              "raw_text" TEXT,
              "created_at" TEXT NOT NULL,
              "updated_at" TEXT NOT NULL,
              "deleted_at" TEXT
            ) STRICT;
            CREATE INDEX "food_log_entry_logical_day" ON "food_log_entry"("logical_day");

            CREATE TABLE "metric_definition" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "key" TEXT NOT NULL,
              "name" TEXT NOT NULL,
              "unit" TEXT NOT NULL DEFAULT '',
              "value_type" TEXT NOT NULL DEFAULT 'decimal',
              "aggregation" TEXT NOT NULL DEFAULT 'sum'
                CHECK ("aggregation" IN ('sum', 'avg', 'max', 'last')),
              "is_builtin" INTEGER NOT NULL DEFAULT 0,
              "created_at" TEXT NOT NULL,
              "updated_at" TEXT NOT NULL,
              "archived_at" TEXT
            ) STRICT;

            CREATE TABLE "metric_sample" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "metric_id" TEXT NOT NULL REFERENCES "metric_definition"("id") ON DELETE CASCADE,
              "logical_day" TEXT NOT NULL,
              "value" REAL NOT NULL,
              "recorded_at" TEXT NOT NULL,
              "is_estimate" INTEGER NOT NULL DEFAULT 0,
              "source" TEXT NOT NULL DEFAULT 'manual',
              "import_batch_id" TEXT REFERENCES "import_batch"("id") ON DELETE CASCADE,
              "raw_text" TEXT,
              "created_at" TEXT NOT NULL,
              "updated_at" TEXT NOT NULL,
              "deleted_at" TEXT
            ) STRICT;
            CREATE INDEX "metric_sample_day" ON "metric_sample"("metric_id", "logical_day");

            CREATE TABLE "goal" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "metric_key" TEXT NOT NULL,
              "comparison" TEXT NOT NULL CHECK ("comparison" IN ('atLeast', 'atMost')),
              "target" REAL NOT NULL,
              "active_from" TEXT NOT NULL,
              "created_at" TEXT NOT NULL,
              "updated_at" TEXT NOT NULL,
              "deleted_at" TEXT
            ) STRICT;

            CREATE TABLE "insight_memory" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "detector_id" TEXT NOT NULL,
              "detector_version" INTEGER NOT NULL,
              "subject_key" TEXT NOT NULL,
              "last_shown_at" TEXT,
              "times_shown" INTEGER NOT NULL DEFAULT 0,
              "times_dismissed" INTEGER NOT NULL DEFAULT 0,
              "snoozed_until" TEXT,
              "feedback" TEXT
            ) STRICT;

            CREATE TABLE "change_log" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "table_name" TEXT NOT NULL,
              "row_id" TEXT NOT NULL,
              "action" TEXT NOT NULL CHECK ("action" IN ('insert', 'update', 'delete')),
              "before_json" TEXT,
              "after_json" TEXT,
              "changed_at" TEXT NOT NULL
            ) STRICT;
            CREATE INDEX "change_log_row" ON "change_log"("table_name", "row_id");
            """)

        // One running block per kind. Enforced by triggers, not a partial
        // UNIQUE index, because CloudKit sync forbids non-PK UNIQUE constraints.
        for event in ["INSERT", "UPDATE OF \"end_utc\", \"deleted_at\", \"kind\""] {
            let name = event.hasPrefix("INSERT") ? "insert" : "update"
            try db.execute(sql: """
                CREATE TRIGGER "time_block_one_running_per_kind_\(name)"
                BEFORE \(event) ON "time_block"
                WHEN NEW."end_utc" IS NULL AND NEW."deleted_at" IS NULL
                BEGIN
                  SELECT RAISE(ABORT, 'a block of this kind is already running')
                  WHERE EXISTS (
                    SELECT 1 FROM "time_block"
                    WHERE "kind" = NEW."kind" AND "end_utc" IS NULL
                      AND "deleted_at" IS NULL AND "id" <> NEW."id"
                  );
                END;
                """)
        }

        let epoch = "1970-01-01 00:00:00.000"
        try db.execute(
            sql: """
                INSERT INTO "metric_definition"
                  ("id", "key", "name", "unit", "value_type", "aggregation", "is_builtin", "created_at", "updated_at")
                VALUES
                  (?, 'steps', 'Steps', 'steps', 'int', 'sum', 1, ?, ?),
                  (?, 'active_kcal', 'Burn', 'kcal', 'decimal', 'sum', 1, ?, ?)
                """,
            arguments: [
                BuiltinMetric.steps.uuidString.lowercased(), epoch, epoch,
                BuiltinMetric.activeKcal.uuidString.lowercased(), epoch, epoch,
            ]
        )
    }

    // MARK: Views

    /// `daily_metric`: one row per (day, metric), aggregated by the metric's rule.
    /// `daily_facts`: one row per logged day; feeds every chart and insight.
    ///
    /// "Not logged" is not zero: a column is NULL when nothing of that kind was
    /// logged that day. Running blocks (`end_utc IS NULL`) and soft-deleted rows
    /// are excluded. Durations come from instants (`julianday` difference).
    static func v1Views(_ db: Database) throws {
        try db.execute(sql: """
            CREATE VIEW "daily_metric" AS
            SELECT
              s."logical_day" AS "logical_day",
              d."id" AS "metric_id",
              d."key" AS "metric_key",
              CASE d."aggregation"
                WHEN 'sum' THEN SUM(s."value")
                WHEN 'avg' THEN AVG(s."value")
                WHEN 'max' THEN MAX(s."value")
                WHEN 'last' THEN (
                  SELECT s2."value" FROM "metric_sample" s2
                  WHERE s2."metric_id" = d."id" AND s2."logical_day" = s."logical_day"
                    AND s2."deleted_at" IS NULL
                  ORDER BY s2."recorded_at" DESC, s2."created_at" DESC
                  LIMIT 1
                )
              END AS "value",
              COUNT(*) AS "sample_count",
              MAX(s."is_estimate") AS "has_estimate"
            FROM "metric_sample" s
            JOIN "metric_definition" d ON d."id" = s."metric_id"
            WHERE s."deleted_at" IS NULL
            GROUP BY s."logical_day", d."id";

            CREATE VIEW "daily_facts" AS
            WITH
              "days" AS (
                SELECT "logical_day" FROM "time_block" WHERE "deleted_at" IS NULL AND "end_utc" IS NOT NULL
                UNION
                SELECT "logical_day" FROM "food_log_entry" WHERE "deleted_at" IS NULL
                UNION
                SELECT "logical_day" FROM "metric_sample" WHERE "deleted_at" IS NULL
              ),
              "blocks" AS (
                SELECT
                  "logical_day",
                  SUM(CASE WHEN "kind" = 'work' THEN "minutes" END) AS "work_min",
                  NULLIF(COUNT(CASE WHEN "kind" = 'work' THEN 1 END), 0) AS "work_blocks",
                  SUM(CASE WHEN "kind" = 'sleep' THEN "minutes" END) AS "sleep_min",
                  SUM(CASE WHEN "kind" = 'nature_call' THEN "minutes" END) AS "nc_min",
                  NULLIF(COUNT(CASE WHEN "kind" = 'nature_call' THEN 1 END), 0) AS "nc_count",
                  MAX("is_estimate") AS "blocks_estimated"
                FROM (
                  SELECT
                    "logical_day", "kind", "is_estimate",
                    CAST(round((julianday("end_utc") - julianday("start_utc")) * 1440) AS INTEGER) AS "minutes"
                  FROM "time_block"
                  WHERE "deleted_at" IS NULL AND "end_utc" IS NOT NULL
                )
                GROUP BY "logical_day"
              ),
              "food" AS (
                SELECT
                  "logical_day",
                  SUM("kcal") AS "kcal",
                  SUM("protein_g") AS "protein_g",
                  SUM("caffeine_mg") AS "caffeine_mg",
                  COUNT(*) AS "food_entries",
                  SUM("kcal" IS NULL AND "protein_g" IS NULL AND "caffeine_mg" IS NULL) AS "food_needing_values",
                  MAX("is_estimate") AS "food_estimated"
                FROM "food_log_entry"
                WHERE "deleted_at" IS NULL
                GROUP BY "logical_day"
              )
            SELECT
              d."logical_day" AS "logical_day",
              b."work_min" AS "work_min",
              b."work_blocks" AS "work_blocks",
              b."sleep_min" AS "sleep_min",
              b."nc_count" AS "nc_count",
              b."nc_min" AS "nc_min",
              f."kcal" AS "kcal",
              f."protein_g" AS "protein_g",
              f."caffeine_mg" AS "caffeine_mg",
              f."food_entries" AS "food_entries",
              f."food_needing_values" AS "food_needing_values",
              burn."value" AS "burn_kcal",
              steps."value" AS "steps",
              CASE WHEN f."kcal" IS NOT NULL AND burn."value" IS NOT NULL
                THEN f."kcal" - burn."value" END AS "net_kcal",
              (COALESCE(b."blocks_estimated", 0) OR COALESCE(f."food_estimated", 0)
                OR COALESCE(burn."has_estimate", 0) OR COALESCE(steps."has_estimate", 0)) AS "has_estimate"
            FROM "days" d
            LEFT JOIN "blocks" b ON b."logical_day" = d."logical_day"
            LEFT JOIN "food" f ON f."logical_day" = d."logical_day"
            LEFT JOIN "daily_metric" burn ON burn."logical_day" = d."logical_day" AND burn."metric_key" = 'active_kcal'
            LEFT JOIN "daily_metric" steps ON steps."logical_day" = d."logical_day" AND steps."metric_key" = 'steps';
            """)
    }

    // MARK: v2

    /// Library foods created by an import remember their batch, so undo can remove them.
    static func v2FoodImportBatch(_ db: Database) throws {
        try db.execute(sql: """
            ALTER TABLE "food" ADD COLUMN "import_batch_id" TEXT REFERENCES "import_batch"("id") ON DELETE SET NULL
            """)
        try installChangeLogTriggers(db, table: "food")
    }

    // MARK: v3

    /// Carbs, fat and nicotine on the dictionary and on every entry, and in
    /// `daily_facts`. Old rows get NULL (unknown), never zero.
    static func v3MacrosAndNicotine(_ db: Database) throws {
        for table in ["food", "food_log_entry"] {
            for column in ["carbs_g", "fat_g", "nicotine_mg"] {
                try db.execute(sql: "ALTER TABLE \"\(table)\" ADD COLUMN \"\(column)\" REAL")
            }
            try installChangeLogTriggers(db, table: table)
        }
        try db.execute(sql: """
            DROP VIEW "daily_facts";

            CREATE VIEW "daily_facts" AS
            WITH
              "days" AS (
                SELECT "logical_day" FROM "time_block" WHERE "deleted_at" IS NULL AND "end_utc" IS NOT NULL
                UNION
                SELECT "logical_day" FROM "food_log_entry" WHERE "deleted_at" IS NULL
                UNION
                SELECT "logical_day" FROM "metric_sample" WHERE "deleted_at" IS NULL
              ),
              "blocks" AS (
                SELECT
                  "logical_day",
                  SUM(CASE WHEN "kind" = 'work' THEN "minutes" END) AS "work_min",
                  NULLIF(COUNT(CASE WHEN "kind" = 'work' THEN 1 END), 0) AS "work_blocks",
                  SUM(CASE WHEN "kind" = 'sleep' THEN "minutes" END) AS "sleep_min",
                  SUM(CASE WHEN "kind" = 'nature_call' THEN "minutes" END) AS "nc_min",
                  NULLIF(COUNT(CASE WHEN "kind" = 'nature_call' THEN 1 END), 0) AS "nc_count",
                  MAX("is_estimate") AS "blocks_estimated"
                FROM (
                  SELECT
                    "logical_day", "kind", "is_estimate",
                    CAST(round((julianday("end_utc") - julianday("start_utc")) * 1440) AS INTEGER) AS "minutes"
                  FROM "time_block"
                  WHERE "deleted_at" IS NULL AND "end_utc" IS NOT NULL
                )
                GROUP BY "logical_day"
              ),
              "food" AS (
                SELECT
                  "logical_day",
                  SUM("kcal") AS "kcal",
                  SUM("protein_g") AS "protein_g",
                  SUM("carbs_g") AS "carbs_g",
                  SUM("fat_g") AS "fat_g",
                  SUM("caffeine_mg") AS "caffeine_mg",
                  SUM("nicotine_mg") AS "nicotine_mg",
                  COUNT(*) AS "food_entries",
                  SUM("kcal" IS NULL AND "protein_g" IS NULL AND "carbs_g" IS NULL AND "fat_g" IS NULL
                      AND "caffeine_mg" IS NULL AND "nicotine_mg" IS NULL) AS "food_needing_values",
                  MAX("is_estimate") AS "food_estimated"
                FROM "food_log_entry"
                WHERE "deleted_at" IS NULL
                GROUP BY "logical_day"
              )
            SELECT
              d."logical_day" AS "logical_day",
              b."work_min" AS "work_min",
              b."work_blocks" AS "work_blocks",
              b."sleep_min" AS "sleep_min",
              b."nc_count" AS "nc_count",
              b."nc_min" AS "nc_min",
              f."kcal" AS "kcal",
              f."protein_g" AS "protein_g",
              f."carbs_g" AS "carbs_g",
              f."fat_g" AS "fat_g",
              f."caffeine_mg" AS "caffeine_mg",
              f."nicotine_mg" AS "nicotine_mg",
              f."food_entries" AS "food_entries",
              f."food_needing_values" AS "food_needing_values",
              burn."value" AS "burn_kcal",
              steps."value" AS "steps",
              CASE WHEN f."kcal" IS NOT NULL AND burn."value" IS NOT NULL
                THEN f."kcal" - burn."value" END AS "net_kcal",
              (COALESCE(b."blocks_estimated", 0) OR COALESCE(f."food_estimated", 0)
                OR COALESCE(burn."has_estimate", 0) OR COALESCE(steps."has_estimate", 0)) AS "has_estimate"
            FROM "days" d
            LEFT JOIN "blocks" b ON b."logical_day" = d."logical_day"
            LEFT JOIN "food" f ON f."logical_day" = d."logical_day"
            LEFT JOIN "daily_metric" burn ON burn."logical_day" = d."logical_day" AND burn."metric_key" = 'active_kcal'
            LEFT JOIN "daily_metric" steps ON steps."logical_day" = d."logical_day" AND steps."metric_key" = 'steps';
            """)
    }

    // MARK: v4

    /// Meals: a named group of dictionary items ("breakfast = coffee + 2 eggs").
    /// Logging a meal writes one ordinary food entry per item.
    static func v4Meals(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE "meal" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "name" TEXT NOT NULL,
              "aliases" TEXT NOT NULL DEFAULT '[]',
              "created_at" TEXT NOT NULL,
              "updated_at" TEXT NOT NULL,
              "archived_at" TEXT
            ) STRICT;

            CREATE TABLE "meal_item" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "meal_id" TEXT NOT NULL REFERENCES "meal"("id") ON DELETE CASCADE,
              "food_id" TEXT NOT NULL REFERENCES "food"("id") ON DELETE CASCADE,
              "servings" REAL NOT NULL DEFAULT 1,
              "quantity" REAL,
              "unit" TEXT,
              "sort" INTEGER NOT NULL DEFAULT 0
            ) STRICT;
            CREATE INDEX "meal_item_meal" ON "meal_item"("meal_id");
            """)
    }

    // MARK: Change log

    /// Tables whose every insert/update/delete is recorded in `change_log` with
    /// before/after JSON. If a later migration alters one of these tables, it
    /// must call `installChangeLogTriggers` again so new columns are captured.
    public static let auditedTables = ["time_block", "food_log_entry", "metric_sample", "food", "category"]

    static func v1ChangeLog(_ db: Database) throws {
        for table in auditedTables {
            try installChangeLogTriggers(db, table: table)
        }
    }

    /// (Re)creates the three change-log triggers for `table` from its current columns.
    ///
    /// `changed_at` comes from the row's own `updated_at`, which the write path
    /// sets from the injected clock; hard deletes (import undo) use SQLite's clock.
    public static func installChangeLogTriggers(_ db: Database, table: String) throws {
        let columns = try db.columns(in: table).map(\.name)
        func json(_ alias: String) -> String {
            "json_object(" + columns.map { "'\($0)', \(alias).\"\($0)\"" }.joined(separator: ", ") + ")"
        }
        let newID = """
            lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' || substr(hex(randomblob(2)), 2) || '-' || \
            substr('89ab', 1 + (abs(random()) % 4), 1) || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6)))
            """
        let hasUpdatedAt = columns.contains("updated_at")
        let newStamp = hasUpdatedAt ? "NEW.\"updated_at\"" : "strftime('%Y-%m-%d %H:%M:%f', 'now')"
        for action in ["insert", "update", "delete"] {
            try db.execute(sql: "DROP TRIGGER IF EXISTS \"\(table)_change_log_\(action)\"")
        }
        try db.execute(sql: """
            CREATE TRIGGER "\(table)_change_log_insert" AFTER INSERT ON "\(table)"
            BEGIN
              INSERT INTO "change_log" ("id", "table_name", "row_id", "action", "before_json", "after_json", "changed_at")
              VALUES (\(newID), '\(table)', NEW."id", 'insert', NULL, \(json("NEW")), \(newStamp));
            END;

            CREATE TRIGGER "\(table)_change_log_update" AFTER UPDATE ON "\(table)"
            BEGIN
              INSERT INTO "change_log" ("id", "table_name", "row_id", "action", "before_json", "after_json", "changed_at")
              VALUES (\(newID), '\(table)', NEW."id", 'update', \(json("OLD")), \(json("NEW")), \(newStamp));
            END;

            CREATE TRIGGER "\(table)_change_log_delete" AFTER DELETE ON "\(table)"
            BEGIN
              INSERT INTO "change_log" ("id", "table_name", "row_id", "action", "before_json", "after_json", "changed_at")
              VALUES (\(newID), '\(table)', OLD."id", 'delete', \(json("OLD")), NULL, strftime('%Y-%m-%d %H:%M:%f', 'now'));
            END;
            """)
    }
}
