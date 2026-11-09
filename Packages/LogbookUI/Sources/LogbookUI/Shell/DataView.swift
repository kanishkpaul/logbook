import AppKit
import LogbookCore
import LogbookPersistence
import Observation
import SwiftUI

/// Backups and exports.
@Observable
public final class DataModel {
    public let store: LogStore
    public let backups: Backups
    public private(set) var snapshots: [URL] = []
    public var message: String?
    /// Also copy each snapshot here (e.g. iCloud Drive). Never the live database.
    public var mirrorFolder: URL? {
        didSet { UserDefaults.standard.set(mirrorFolder?.path, forKey: "backupMirrorPath") }
    }

    public init(store: LogStore, backups: Backups? = nil) {
        self.store = store
        self.backups = backups ?? Backups(database: store.database)
        mirrorFolder = UserDefaults.standard.string(forKey: "backupMirrorPath").map { URL(filePath: $0, directoryHint: .isDirectory) }
        reload()
    }

    private func mirrorIfSet() {
        guard let mirrorFolder else { return }
        do {
            try backups.mirror(to: mirrorFolder)
        } catch {
            message = "Mirror failed: \(error.localizedDescription)"
        }
    }

    public var exportsDirectory: URL { AppDatabase.defaultDirectory.appending(path: "Exports") }

    public func reload() {
        snapshots = backups.list()
    }

    /// Today's snapshot if missing (called on launch and hourly).
    public func ensureDaily() {
        do {
            if try backups.ensureDaily(day: store.boundary.logicalDay(containing: store.now(), in: store.timeZone())) != nil {
                mirrorIfSet()
                reload()
            }
        } catch {
            message = "Backup failed: \(error)"
        }
    }

    public func backUpNow() {
        do {
            let url = try backups.backUp(day: store.boundary.logicalDay(containing: store.now(), in: store.timeZone()))
            message = "Backed up to \(url.lastPathComponent)"
            mirrorIfSet()
            reload()
        } catch {
            message = "Backup failed: \(error)"
        }
    }

    private var stamp: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = store.timeZone()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: store.now())
    }

    public func exportJSON() {
        do {
            try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
            let url = exportsDirectory.appending(path: "logbook-\(stamp).json")
            try DataExport.json(store.database, exportedAt: store.now()).write(to: url)
            message = "Exported \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            message = "Export failed: \(error)"
        }
    }

    public func exportCSV() {
        do {
            let dir = exportsDirectory.appending(path: "logbook-csv-\(stamp)")
            try DataExport.csv(store.database, to: dir)
            message = "Exported CSVs to \(dir.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } catch {
            message = "Export failed: \(error)"
        }
    }

    public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

public struct DataView: View {
    let model: DataModel

    public init(model: DataModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                HStack {
                    Button("Back up now") { model.backUpNow() }
                    Button("Show in Finder") { model.reveal(model.backups.directory) }
                }
                if model.snapshots.isEmpty {
                    Text("No snapshots yet").foregroundStyle(.secondary)
                }
                ForEach(model.snapshots, id: \.self) { url in
                    HStack {
                        Text(url.lastPathComponent).monospaced()
                        Spacer()
                        Button("Reveal") { model.reveal(url) }.buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Backups")
            } footer: {
                Text("A snapshot is taken every day the app runs; the last 30 are kept. To restore, quit Logbook and copy a snapshot over logbook.sqlite (or use `logbook-import restore`).")
            }

            Section {
                Toggle("Also keep a copy in iCloud Drive", isOn: Binding(
                    get: { model.mirrorFolder != nil },
                    set: { on in model.mirrorFolder = on ? Backups.iCloudDriveFolder : nil; if on { model.backUpNow() } }
                ))
                .disabled(Backups.iCloudDriveFolder == nil && model.mirrorFolder == nil)
                if let folder = model.mirrorFolder {
                    HStack {
                        Text(folder.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Spacer()
                        Button("Reveal") { model.reveal(folder) }.buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Mirror")
            } footer: {
                Text(Backups.iCloudDriveFolder == nil
                     ? "iCloud Drive isn't on for this Mac."
                     : "Snapshots are copied to iCloud Drive › Logbook Backups. The live database never leaves this Mac.")
            }

            Section {
                HStack {
                    Button("Export JSON") { model.exportJSON() }
                    Button("Export CSV") { model.exportCSV() }
                }
            } header: {
                Text("Export")
            } footer: {
                Text("JSON holds every table and restores exactly. CSV gives one file per table plus daily_facts.csv for spreadsheets.")
            }

            if let message = model.message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Data")
        .onAppear { model.reload() }
    }
}

#Preview("Data") {
    DataView(model: DataModel(store: PreviewSupport.store(), backups: Backups(database: PreviewSupport.store().database, directory: FileManager.default.temporaryDirectory.appending(path: "logbook-preview-backups"))))
        .frame(width: 600, height: 500)
}
