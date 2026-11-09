import LogbookPersistence
import SwiftUI

/// Permissions and storage checks (M0). Each row has the action that exercises it.
struct DiagnosticsView: View {
    let model: DiagnosticsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Notifications") {
                    HStack {
                        Text(model.notifications).monospaced()
                        Button("Request") { Task { await model.requestNotifications() } }
                        Button("Send test") { Task { await model.sendTestNotification() } }
                    }
                }
                LabeledContent("Login item") {
                    HStack {
                        Text(model.loginItem).monospaced()
                        Button("Toggle") { Task { await model.toggleLoginItem() } }
                        Button("Settings…") { model.openLoginItemsSettings() }
                    }
                }
                LabeledContent("Calendar (EventKit)") {
                    HStack {
                        Text(model.calendar).monospaced()
                        if let n = model.calendarCount { Text("\(n) calendars").foregroundStyle(.secondary) }
                        Button("Request") { Task { await model.requestCalendar() } }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("These should survive a rebuild. `make spike-status` shows what the last launch recorded.")
            }

            Section("Quick Entry") {
                LabeledContent("Global shortcut") { Text(model.quickEntryShortcut).monospaced() }
            }

            Section("Storage") {
                LabeledContent("Live database") { Text(model.database).monospaced() }
                LabeledContent("Folder") {
                    Text(AppDatabase.defaultDirectory.path).textSelection(.enabled).foregroundStyle(.secondary)
                }
            }

            if let error = model.lastError {
                Section("Last error") { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }

            Section {
                Button("Refresh") { Task { await model.refreshAndRecord() } }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Diagnostics")
        .task { await model.refresh() }
    }
}

#Preview("Diagnostics") {
    DiagnosticsView(model: DiagnosticsModel(databaseCheck: { "ok (preview)" }))
}
