import SwiftUI

/// Today's entries: blocks, food (with totals) and body metrics. Right-click to delete.
struct DayLogList: View {
    let model: TodayModel
    let state: TodayState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Blocks", empty: "No blocks yet") {
                ForEach(state.blocks) { row in
                    HStack {
                        Image(systemName: row.domain.symbol).foregroundStyle(row.domain.color).frame(width: 20)
                        Text(row.title)
                        Spacer()
                        Text(row.times).foregroundStyle(.secondary).monospacedDigit()
                        Text((row.isEstimate ? "~" : "") + row.duration).monospacedDigit().frame(width: 70, alignment: .trailing)
                    }
                    .contextMenu {
                        Button(row.isRunning ? "Discard timer" : "Delete", role: .destructive) { model.discardBlock(row.id) }
                    }
                }
            } isEmpty: { state.blocks.isEmpty }

            section("Food", empty: "Nothing logged yet") {
                ForEach(state.foods) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.time).foregroundStyle(.secondary).monospacedDigit().frame(width: 44, alignment: .leading)
                        Text((row.isEstimate ? "~ " : "") + row.name)
                        Spacer()
                        Text(row.summary)
                            .foregroundStyle(row.needsValues ? .orange : .secondary)
                            .lineLimit(1)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) { model.deleteFood(row.id) }
                    }
                }
                if !state.foodTotals.isEmpty {
                    Divider()
                    HStack(spacing: 14) {
                        Text("Total").fontWeight(.medium)
                        Spacer()
                        ForEach(state.foodTotals, id: \.label) { part in
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(part.value) \(part.unit)").monospacedDigit()
                                Text(part.label).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } isEmpty: { state.foods.isEmpty }

            section("Body", empty: "No burn or steps yet") {
                ForEach(state.samples) { row in
                    HStack {
                        Text(row.title)
                        Spacer()
                        Text(row.value).monospacedDigit()
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) { model.deleteSample(row.id) }
                    }
                }
            } isEmpty: { state.samples.isEmpty }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, empty: String, @ViewBuilder content: () -> Content, isEmpty: () -> Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if isEmpty() {
                Text(empty).foregroundStyle(.tertiary)
            } else {
                content()
            }
        }
    }
}

#Preview("Day log") {
    let model = PreviewSupport.todayModel()
    return ScrollView {
        if let state = model.state { DayLogList(model: model, state: state).padding() }
    }
    .frame(width: 640, height: 500)
}
