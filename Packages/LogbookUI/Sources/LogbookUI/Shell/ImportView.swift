import LogbookCore
import LogbookImport
import LogbookPersistence
import SwiftUI

/// Paste from Notes: preview what would be imported, then apply as one
/// undoable batch. Same parser and rules as the `logbook-import` command.
public struct ImportView: View {
    let store: LogStore
    @State private var text = ""
    @State private var plan: ImportPlan?
    @State private var message: String?
    @State private var batches: [ImportBatch] = []

    public init(store: LogStore) {
        self.store = store
    }

    private var importer: Importer {
        Importer(store: store, timeZone: store.timeZone(), defaultYear: store.boundary.logicalDay(containing: store.now(), in: store.timeZone()).year)
    }

    public var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste a day (or many) from Notes").font(.headline)
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .onChange(of: text) { preview() }
                Text("Format: docs/IMPORT_FORMAT.md. Start each day with a date line, e.g. “Fri 10 Oct 2026”.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 320)

            VStack(alignment: .leading, spacing: 10) {
                if let plan {
                    Text("\(plan.days.count) days · \(plan.blocks.count) blocks · \(plan.foodEntries.count) foods · \(plan.samples.count) samples · \(plan.newFoods.count) new dictionary entries")
                        .font(.headline)
                    if plan.alreadyImported > 0 { Text("\(plan.alreadyImported) rows already imported (skipped)").foregroundStyle(.secondary) }
                    List {
                        ForEach(plan.days, id: \.day) { d in
                            Text("\(d.day.description)  ·  blocks \(d.blocks)  ·  foods \(d.foods)  ·  work \(Durations.compact(minutes: d.workMin))  ·  \(Int(d.kcal.rounded())) kcal")
                                .monospacedDigit()
                        }
                        ForEach(Array(plan.issues.enumerated()), id: \.offset) { _, issue in
                            Label(issue.description, systemImage: issue.severity == .info ? "info.circle" : "exclamationmark.triangle")
                                .foregroundStyle(issue.severity == .error ? .red : issue.severity == .warning ? .orange : .secondary)
                        }
                    }
                    Button("Import") { apply(plan) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(plan.isEmpty)
                } else {
                    ContentUnavailableView("Nothing to preview", systemImage: "doc.on.clipboard")
                }
                if let message { Text(message).foregroundStyle(.secondary) }
                Divider()
                Text("Imports").font(.headline)
                List(batches, id: \.id) { b in
                    HStack {
                        Text(b.sourceName)
                        Text(b.importedAt, style: .date).foregroundStyle(.secondary)
                        Spacer()
                        if b.undoneAt == nil {
                            Button("Undo") { undo(b.id) }
                        } else {
                            Text("undone").foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 120)
            }
            .padding()
            .frame(minWidth: 360)
        }
        .navigationTitle("Import")
        .onAppear(perform: reloadBatches)
    }

    private func preview() {
        plan = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try? importer.preview(text, sourceName: "Pasted from Notes")
    }

    private func apply(_ plan: ImportPlan) {
        do {
            try importer.apply(plan)
            message = "Imported \(plan.rowCount) rows."
            text = ""
            self.plan = nil
        } catch {
            message = "Import failed: \(error)"
        }
        reloadBatches()
    }

    private func undo(_ id: UUID) {
        do {
            try importer.undo(batchID: id)
            message = "Import undone."
        } catch {
            message = "\(error)"
        }
        reloadBatches()
    }

    private func reloadBatches() {
        batches = (try? importer.batches()) ?? []
    }
}

#Preview("Import") {
    ImportView(store: PreviewSupport.store())
        .frame(width: 900, height: 600)
}
