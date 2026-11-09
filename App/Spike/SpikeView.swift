import LogbookUI
import SwiftUI

/// M0 spike window: one row per check, with the action that exercises it.
struct SpikeView: View {
    let model: SpikeModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                LabeledContent("Menu bar timer") {
                    HStack {
                        if let start = model.timerStart {
                            RunningTimerLabel(title: model.timerTitle, start: start)
                        } else {
                            Text("stopped").foregroundStyle(.secondary)
                        }
                        Button(model.timerStart == nil ? "Start" : "Stop") { model.toggleTimer() }
                    }
                }
            } header: {
                Text("M0 spike")
            } footer: {
                Text("Check the menu bar label keeps counting while this window is closed.")
            }

            Section("Permissions (should survive a rebuild)") {
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
            }

            Section("Storage") {
                LabeledContent("Live database") { Text(model.database).monospaced() }
            }

            if let error = model.lastError {
                Section("Last error") { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }

            Section {
                Button("Refresh") { Task { await model.refreshAndRecord() } }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.openMainWindow = { openWindow(id: "main") } }
    }
}

/// The menu bar panel: timer control and a way back to the window.
struct MenuBarPanel: View {
    let model: SpikeModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let start = model.timerStart {
                RunningTimerLabel(title: model.timerTitle, start: start).font(.title3)
            } else {
                Text("No timer running").foregroundStyle(.secondary)
            }
            HStack {
                Button(model.timerStart == nil ? "Start study" : "Stop") { model.toggleTimer() }
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Open Logbook") {
                    NSApplication.shared.activate()
                    model.openMainWindow?()
                }
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 260)
    }
}

#Preview("Spike window") {
    SpikeView(model: SpikeModel())
}

#Preview("Menu bar panel") {
    MenuBarPanel(model: SpikeModel())
}
