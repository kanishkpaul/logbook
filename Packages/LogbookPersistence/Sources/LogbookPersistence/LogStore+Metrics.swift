import Foundation
import GRDB
import LogbookCore
import SQLiteData

extension LogStore {
    public enum MetricError: Error, Equatable {
        case nameTaken(String)
        case builtin
        case emptyName
    }

    /// Metric definitions, built-ins first, then yours by name.
    public func metricDefinitions(includeArchived: Bool = false) throws -> [MetricDefinition] {
        try database.read { db in
            try MetricDefinition
                .where { includeArchived || $0.archivedAt.is(nil) }
                .order { ($0.isBuiltin.desc(), $0.name.collate(.nocase)) }
                .fetchAll(db)
        }
    }

    /// `"Body weight"` → `"body_weight"`.
    public static func metricKey(_ name: String) -> String {
        name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "_")
    }

    /// Adds a custom metric. It then gets logging ("weight 71.2"), charts,
    /// baselines and the unusual-day insight like the built-in ones.
    @discardableResult
    public func addMetric(name: String, unit: String = "", aggregation: MetricAggregation = .last, valueType: String = "decimal") throws -> MetricDefinition {
        let clean = name.trimmingCharacters(in: .whitespaces)
        let key = Self.metricKey(clean)
        guard !key.isEmpty else { throw MetricError.emptyName }
        let t = now()
        return try database.write { db in
            let existing = try MetricDefinition.where { $0.archivedAt.is(nil) }.fetchAll(db)
            if existing.contains(where: { $0.key == key || $0.name.lowercased() == clean.lowercased() }) || ["work", "sleep", "burn", "kcal"].contains(key) {
                throw MetricError.nameTaken(clean)
            }
            let def = MetricDefinition(id: uuid(), key: key, name: clean, unit: unit, valueType: valueType,
                                       aggregation: aggregation, createdAt: t, updatedAt: t)
            try MetricDefinition.insert { def }.execute(db)
            return def
        }
    }

    /// Hides a custom metric (its samples stay in history). Built-ins can't be archived.
    public func archiveMetric(id: MetricDefinition.ID) throws {
        let t = now()
        try database.write { db in
            guard var def = try MetricDefinition.find(id).fetchOne(db) else { throw Failure.notFound(id) }
            guard !def.isBuiltin else { throw MetricError.builtin }
            def.archivedAt = t
            def.updatedAt = t
            try MetricDefinition.update(def).execute(db)
        }
    }

    /// The active custom metric whose name or key is `text` (case-insensitive).
    public func customMetric(named text: String) throws -> MetricDefinition? {
        let k = Self.metricKey(text)
        return try metricDefinitions().first { !$0.isBuiltin && ($0.key == k || $0.name.lowercased() == text.lowercased()) }
    }

    /// Per-day values of custom metrics in a range, by key (via `daily_metric`).
    static func customValues(_ db: Database, first: LogicalDay, last: LogicalDay) throws -> [String: [LogicalDay: Double]] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT dm.metric_key, dm.logical_day, dm.value FROM daily_metric dm
            JOIN metric_definition d ON d.id = dm.metric_id
            WHERE d.is_builtin = 0 AND d.archived_at IS NULL AND dm.logical_day BETWEEN ? AND ?
            """, arguments: [first.description, last.description])
        var out: [String: [LogicalDay: Double]] = [:]
        for r in rows {
            guard let day = LogicalDay(r["logical_day"] as String), let v = r["value"] as Double? else { continue }
            out[r["metric_key"] as String, default: [:]][day] = v
        }
        return out
    }
}
