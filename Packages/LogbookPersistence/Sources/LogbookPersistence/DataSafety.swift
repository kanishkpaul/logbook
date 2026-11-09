import Foundation
import GRDB
import LogbookCore

/// Daily snapshots of the database (principle 5: your history is sacred).
///
/// Snapshots are made with `VACUUM INTO`, a consistent copy taken while the
/// app keeps running. They live in `<data folder>/Backups/`, never in a synced
/// folder; only snapshots (never the live file) may be mirrored elsewhere.
public struct Backups: Sendable {
    public let database: any DatabaseWriter
    public let directory: URL
    /// How many snapshots to keep (newest first).
    public var keep: Int

    public init(database: any DatabaseWriter, directory: URL = AppDatabase.defaultDirectory.appending(path: "Backups"), keep: Int = 30) {
        self.database = database
        self.directory = directory
        self.keep = keep
    }

    public static func fileName(for day: LogicalDay) -> String { "logbook-\(day).sqlite" }

    /// Snapshots, newest first.
    public func list() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("logbook-") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Writes (or replaces) the snapshot for `day`, then prunes old ones.
    @discardableResult
    public func backUp(day: LogicalDay) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appending(path: Self.fileName(for: day))
        let temp = directory.appending(path: ".in-progress-\(UUID().uuidString).sqlite")
        try database.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [temp.path])
        }
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: target)
        }
        try prune()
        return target
    }

    /// Makes today's snapshot if it doesn't exist yet. Returns it when made.
    @discardableResult
    public func ensureDaily(day: LogicalDay) throws -> URL? {
        let target = directory.appending(path: Self.fileName(for: day))
        guard !FileManager.default.fileExists(atPath: target.path) else { return nil }
        return try backUp(day: day)
    }

    func prune() throws {
        for old in list().dropFirst(max(1, keep)) {
            try FileManager.default.removeItem(at: old)
        }
    }
}

/// Full export of every table to JSON (restorable) or CSV (for spreadsheets).
public enum DataExport {
    public static let format = "logbook-export"
    public static let version = 1

    /// Parents before children, so a restore satisfies foreign keys.
    static let restoreOrder = [
        "import_batch", "category", "food", "metric_definition", "meal", "meal_item",
        "task_list", "task", "plan_template", "plan_block",
        "time_block", "food_log_entry", "metric_sample", "goal", "insight_memory", "change_log",
    ]

    static func tables(_ db: Database) throws -> [String] {
        let all = try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
            """)
        let known = restoreOrder.filter(all.contains)
        return known + all.filter { !known.contains($0) }.sorted()
    }

    // MARK: JSON

    /// `{ format, version, exportedAt, migrations, tables: { name: { columns, rows } } }`.
    /// Values are SQLite's own (TEXT/INTEGER/REAL/NULL), so nothing is reinterpreted.
    public static func json(_ reader: any DatabaseReader, exportedAt: Date) throws -> Data {
        let object: [String: Any] = try reader.read { db in
            var out: [String: Any] = [:]
            for table in try tables(db) {
                let columns = try db.columns(in: table).map(\.name)
                let quoted = columns.map { "\"\($0)\"" }.joined(separator: ", ")
                let rows = try Row.fetchAll(db, sql: "SELECT \(quoted) FROM \"\(table)\" ORDER BY rowid")
                out[table] = [
                    "columns": columns,
                    "rows": rows.map { row in columns.map { jsonValue(row[$0] as DatabaseValue) } },
                ]
            }
            return [
                "format": format,
                "version": version,
                "exportedAt": ISO8601DateFormatter().string(from: exportedAt),
                "migrations": try Schema.migrator.appliedIdentifiers(db).sorted(),
                "tables": out,
            ]
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    static func jsonValue(_ v: DatabaseValue) -> Any {
        switch v.storage {
        case .null: NSNull()
        case .int64(let i): i
        case .double(let d): d
        case .string(let s): s
        case .blob(let b): ["base64": b.base64EncodedString()]
        }
    }

    public enum RestoreError: Error, Equatable {
        case notAnExport
        case newerSchema([String])
        case targetNotEmpty
    }

    /// Restores a JSON export into an empty (freshly migrated) database.
    /// The change log is restored as exported, not as re-recorded by triggers.
    public static func restore(_ data: Data, into writer: any DatabaseWriter) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["format"] as? String == format,
              let tables = object["tables"] as? [String: [String: Any]]
        else { throw RestoreError.notAnExport }
        try writer.write { db in
            let applied = Set(try Schema.migrator.appliedIdentifiers(db))
            let needed = (object["migrations"] as? [String]) ?? []
            let missing = needed.filter { !applied.contains($0) }
            guard missing.isEmpty else { throw RestoreError.newerSchema(missing) }
            for table in ["time_block", "food_log_entry", "metric_sample", "food"] {
                guard try Int.fetchOne(db, sql: "SELECT count(*) FROM \"\(table)\"") == 0 else { throw RestoreError.targetNotEmpty }
            }
            let order = try self.tables(db).filter { tables[$0] != nil }
            for table in order where table != "change_log" {
                guard let columns = tables[table]?["columns"] as? [String], let rows = tables[table]?["rows"] as? [[Any]] else { continue }
                let existing = Set(try db.columns(in: table).map(\.name))
                let usable = columns.enumerated().filter { existing.contains($0.element) }
                let sql = "INSERT OR REPLACE INTO \"\(table)\" (\(usable.map { "\"\($0.element)\"" }.joined(separator: ", "))) VALUES (\(usable.map { _ in "?" }.joined(separator: ", ")))"
                let statement = try db.makeStatement(sql: sql)
                for row in rows {
                    let values = usable.map { databaseValue(row[$0.offset]) }
                    try statement.execute(arguments: StatementArguments(values))
                }
            }
            // Triggers logged the restore's own inserts; keep only the exported history.
            try db.execute(sql: "DELETE FROM change_log")
            if let log = tables["change_log"], let columns = log["columns"] as? [String], let rows = log["rows"] as? [[Any]] {
                let sql = "INSERT INTO change_log (\(columns.map { "\"\($0)\"" }.joined(separator: ", "))) VALUES (\(columns.map { _ in "?" }.joined(separator: ", ")))"
                let statement = try db.makeStatement(sql: sql)
                for row in rows { try statement.execute(arguments: StatementArguments(row.map(databaseValue))) }
            }
        }
    }

    static func databaseValue(_ any: Any) -> DatabaseValue {
        switch any {
        case is NSNull: return .null
        case let n as NSNumber:
            if CFNumberIsFloatType(n) { return n.doubleValue.databaseValue }
            return n.int64Value.databaseValue
        case let s as String: return s.databaseValue
        case let d as [String: String]: return d["base64"].flatMap { Data(base64Encoded: $0) }?.databaseValue ?? .null
        default: return .null
        }
    }

    // MARK: CSV

    /// One CSV per table plus `daily_facts.csv`, written into `directory`.
    @discardableResult
    public static func csv(_ reader: any DatabaseReader, to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try reader.read { db in
            var written: [URL] = []
            for name in try tables(db) + ["daily_facts"] {
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM \"\(name)\"" + (name == "daily_facts" ? " ORDER BY logical_day" : " ORDER BY rowid"))
                let columns = try db.columns(in: name).map(\.name)
                var text = columns.map(csvField).joined(separator: ",") + "\n"
                for row in rows {
                    text += columns.map { col -> String in
                        let v: DatabaseValue = row[col]
                        switch v.storage {
                        case .null: return ""
                        case .int64(let i): return String(i)
                        case .double(let d): return String(d)
                        case .string(let s): return csvField(s)
                        case .blob(let b): return b.base64EncodedString()
                        }
                    }.joined(separator: ",") + "\n"
                }
                let url = directory.appending(path: "\(name).csv")
                try text.write(to: url, atomically: true, encoding: .utf8)
                written.append(url)
            }
            return written
        }
    }

    static func csvField(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : s
    }
}
