import ServiceManagement
import SwiftUI

/// App settings. The day boundary is fixed (decision #1: calendar day).
public struct SettingsView: View {
    @Bindable var model: TodayModel
    let quickEntryShortcut: String
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    public init(model: TodayModel, quickEntryShortcut: String = "⌥ Space") {
        self.model = model
        self.quickEntryShortcut = quickEntryShortcut
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Open Logbook at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            } header: {
                Text("General")
            } footer: {
                Text("Works best with the single copy in /Applications (make install).")
            }
            Section("Day") {
                LabeledContent("Day boundary", value: "Calendar day (midnight)")
                Text("Sleep counts toward the day you wake up.").font(.caption).foregroundStyle(.secondary)
            }
            Section("In-system estimates") {
                Stepper(value: $model.caffeineHalfLifeHours, in: 2...10, step: 0.5) {
                    LabeledContent("Caffeine half-life", value: "\(model.caffeineHalfLifeHours.formatted()) h")
                }
                Stepper(value: $model.nicotineHalfLifeHours, in: 0.5...4, step: 0.25) {
                    LabeledContent("Nicotine half-life", value: "\(model.nicotineHalfLifeHours.formatted()) h")
                }
                Text("Simple decay models for a rough “how much is still in me”. Not medical advice.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ForEach(NotificationKind.allCases) { kind in
                    Toggle(kind.title, isOn: Binding(
                        get: { model.enabledNotifications.contains(kind) },
                        set: { on in
                            if on { model.enabledNotifications.insert(kind) } else { model.enabledNotifications.remove(kind) }
                        }
                    ))
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("At most 2 a day that you didn't ask for (close the day, caffeine cutoff, insight, weekly review). None during your usual sleep or a running sleep timer. A kind you ignore three times in a row drops to every other day.")
            }
            Section {
                Toggle("Phrase recaps with Apple Intelligence", isOn: Binding(
                    get: { model.recaps.useOnDeviceModel }, set: { model.recaps.useOnDeviceModel = $0 }
                ))
                .disabled(!model.recaps.modelAvailable)
            } header: {
                Text("Recaps")
            } footer: {
                Text(model.recaps.modelAvailable
                     ? "On this Mac and offline. The model only writes words around numbers the app computed; anything off is replaced by the plain summary."
                     : "Apple Intelligence isn't available on this Mac, so recaps use the plain summary.")
            }
            Section("Quick Entry") {
                LabeledContent("Global shortcut", value: quickEntryShortcut)
                LabeledContent("In the app", value: "⌘ L")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }
}

#Preview("Settings") {
    SettingsView(model: PreviewSupport.todayModel())
}
