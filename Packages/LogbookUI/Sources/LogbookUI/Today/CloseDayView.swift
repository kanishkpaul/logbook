import LogbookCore
import LogbookImport
import SwiftUI

/// The evening sheet: unlogged gaps, missing burn/steps, foods without values,
/// then the day's summary. Everything here is optional.
public struct CloseDayView: View {
    let model: TodayModel
    @Environment(\.dismiss) private var dismiss
    @State private var burn = ""
    @State private var steps = ""
    @State private var values: [UUID: String] = [:]
    @State private var templateName = ""

    public init(model: TodayModel) {
        self.model = model
    }

    public var body: some View {
        let close = model.state?.closeDay
        VStack(alignment: .leading, spacing: 16) {
            Text("Close the day").font(.title2.bold())
            if let close {
                Form {
                    if !close.gaps.isEmpty {
                        Section("Unlogged time while awake") {
                            ForEach(close.gaps) { gap in
                                Text(gap.text).monospacedDigit()
                            }
                            Text("Log them with Quick Entry, e.g. “1400-1530 study”, or leave them.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if close.missingBurn || close.missingSteps {
                        Section("Burn and steps") {
                            if close.missingBurn {
                                LabeledContent("Burn (kcal)") {
                                    TextField("373", text: $burn).frame(width: 100).onSubmit { save("active_kcal", burn) { burn = "" } }
                                }
                            }
                            if close.missingSteps {
                                LabeledContent("Steps") {
                                    TextField("11773", text: $steps).frame(width: 100).onSubmit { save("steps", steps) { steps = "" } }
                                }
                            }
                        }
                    }
                    if !close.foodsNeedingValues.isEmpty {
                        Section("Foods without values") {
                            ForEach(close.foodsNeedingValues) { food in
                                LabeledContent(food.name) {
                                    TextField("kcal / protein / caffeine", text: binding(food.id))
                                        .frame(width: 200)
                                        .onSubmit { fill(food.id) }
                                }
                            }
                            Text("Same shorthand as everywhere: `350 / 14 / 0`, tags like `40c 12f 1.2nic`, `~` for estimates.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !close.unreviewedPlans.isEmpty {
                        Section("Planned blocks") {
                            ForEach(close.unreviewedPlans) { p in
                                LabeledContent("\(p.title) · \(p.times)") {
                                    HStack {
                                        Button("Done as planned") { model.doneAsPlanned(p.id) }
                                        Button("Skipped") { model.skipPlanned(p.id) }
                                    }
                                }
                            }
                        }
                    }
                    if !close.unfinishedTasks.isEmpty {
                        Section("Unfinished tasks") {
                            ForEach(close.unfinishedTasks) { t in
                                LabeledContent(t.title) {
                                    HStack {
                                        Button("Tomorrow") { model.moveToTomorrow(t.id) }
                                        Button("Someday") { model.somedayTask(t.id) }
                                        Button("Drop") { model.dropTask(t.id) }
                                    }
                                }
                            }
                        }
                    }
                    Section("Plan tomorrow") {
                        let templates = model.templates
                        if templates.isEmpty {
                            Text("No templates yet. Plan a good day, then save it here as one.").foregroundStyle(.secondary)
                        }
                        ForEach(templates, id: \.id) { t in
                            LabeledContent(t.name) {
                                Button("Stamp onto tomorrow") { model.stampTomorrow(t.id) }
                            }
                        }
                        HStack {
                            TextField("Save today's plan as…", text: $templateName)
                            Button("Save") {
                                model.saveTemplate(named: templateName)
                                templateName = ""
                            }
                            .disabled(templateName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        Text("Or type “plan tomorrow 1000-1300 deep work” in Quick Entry.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Today") {
                        ForEach(close.summary, id: \.self) { Text($0) }
                        if close.summary.isEmpty { Text("Nothing logged yet").foregroundStyle(.secondary) }
                    }
                }
                .formStyle(.grouped)
            }
            HStack {
                if let error = model.lastError { Text(error).foregroundStyle(.red).font(.caption) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 420)
    }

    private func binding(_ id: UUID) -> Binding<String> {
        Binding(get: { values[id, default: ""] }, set: { values[id] = $0 })
    }

    private func save(_ key: String, _ text: String, clear: () -> Void) {
        guard let v = Double(text.replacingOccurrences(of: ",", with: "")) else { return }
        model.recordMetric(key, value: v)
        clear()
    }

    private func fill(_ id: UUID) {
        guard let text = values[id], let parsed = NutritionInput.parse(text) else {
            model.lastError = "Couldn't read those values"
            return
        }
        model.fillValues(id, nutrition: parsed.nutrition, isEstimate: parsed.isEstimate)
        values[id] = nil
    }
}

#Preview("Close the day") {
    CloseDayView(model: PreviewSupport.todayModel())
}
