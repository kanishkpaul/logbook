import SwiftUI

/// App settings. The day boundary is fixed (decision #1: calendar day).
public struct SettingsView: View {
    @Bindable var model: TodayModel
    let quickEntryShortcut: String

    public init(model: TodayModel, quickEntryShortcut: String = "⌥ Space") {
        self.model = model
        self.quickEntryShortcut = quickEntryShortcut
    }

    public var body: some View {
        Form {
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
