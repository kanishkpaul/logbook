import Foundation
import GRDB

/// Opens and migrates the logbook database.
public enum AppDatabase {
    /// `~/Library/Application Support/logbook/`. Never inside a synced folder:
    /// only backups/snapshots may be mirrored to iCloud Drive.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "logbook", directoryHint: .isDirectory)
    }

    public static let fileName = "logbook.sqlite"

    /// The live on-disk database (WAL mode via `DatabasePool`), migrated.
    public static func openLive(directory: URL = defaultDirectory) throws -> DatabasePool {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: directory.appending(path: fileName).path, configuration: configuration())
        try Schema.migrator.migrate(pool)
        return pool
    }

    /// A fresh in-memory database for tests and previews, migrated.
    public static func openInMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue(configuration: configuration())
        try Schema.migrator.migrate(queue)
        return queue
    }

    static func configuration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.label = "logbook"
        return config
    }

    /// Number of tables, a cheap "is the database open and migrated" check.
    public static func tableCount(_ reader: any DatabaseReader) throws -> Int {
        try reader.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM sqlite_master WHERE type = 'table'") ?? 0 }
    }

    /// The full schema as SQL, in a stable order (used to regenerate `schema.sql`).
    public static func schemaSQL(_ db: Database) throws -> String {
        let rows = try Row.fetchAll(db, sql: """
            SELECT type, name, sql FROM sqlite_master
            WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
            ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 WHEN 'view' THEN 2 ELSE 3 END, name
            """)
        return rows.map { ($0["sql"] as String) + ";" }.joined(separator: "\n\n") + "\n"
    }
}
