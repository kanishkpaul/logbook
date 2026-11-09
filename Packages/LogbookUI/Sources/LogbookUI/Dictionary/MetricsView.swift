import LogbookCore
import LogbookPersistence
import SwiftUI

/// Your own metrics: weight, mood, water… Each one gets logging (type its name
/// and a number in Quick Entry), charts in Body and Trends, and the
/// unusual-day insight.
public struct MetricsView: View {
    let store: LogStore
    @State private var definitions: [MetricDefinition] = []
    @State private var name = ""
    @State private var unit = ""
    @State private var aggregation: MetricAggregation = .last
    @State private var message: String?

    public init(store: LogStore) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section {
                ForEach(definitions, id: \.id) { def in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(def.name + (def.unit.isEmpty ? "" : " (\(def.unit))"))
                            Text("\(Self.describe(def.aggregation)) · log with “\(def.name.lowercased()) 12”")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if def.isBuiltin {
                            Text("built in").font(.caption).foregroundStyle(.tertiary)
                        } else {
                            Button("Archive") { archive(def) }.buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("Metrics")
            } footer: {
                Text("Archiving hides a metric; what you logged stays in your history and exports.")
            }

            Section("Add a metric") {
                TextField("Name (e.g. Weight, Mood, Water)", text: $name)
                TextField("Unit (optional: kg, ml, 1–5)", text: $unit)
                Picker("Each day counts", selection: $aggregation) {
                    ForEach(MetricAggregation.allCases, id: \.self) { Text(Self.describe($0)).tag($0) }
                }
                Button("Add") { add() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Metrics")
        .onAppear(perform: reload)
    }

    static func describe(_ a: MetricAggregation) -> String {
        switch a {
        case .sum: "the total of the day"
        case .avg: "the average of the day"
        case .max: "the highest of the day"
        case .last: "the last value of the day"
        }
    }

    private func reload() {
        definitions = (try? store.metricDefinitions()) ?? []
    }

    private func add() {
        do {
            let def = try store.addMetric(name: name, unit: unit.trimmingCharacters(in: .whitespaces), aggregation: aggregation)
            message = "Added. Log it with “\(def.name.lowercased()) 12” in Quick Entry."
            name = ""
            unit = ""
            reload()
        } catch LogStore.MetricError.nameTaken(let n) {
            message = "“\(n)” already exists."
        } catch {
            message = "\(error)"
        }
    }

    private func archive(_ def: MetricDefinition) {
        try? store.archiveMetric(id: def.id)
        reload()
    }
}

#Preview("Metrics") {
    NavigationStack { MetricsView(store: PreviewSupport.store()) }.frame(width: 640, height: 600)
}
