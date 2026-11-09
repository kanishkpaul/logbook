import LogbookCore
import LogbookPersistence
import SwiftUI

/// Today's plan: what's up next (with Start / Done as planned / Skip), the
/// planned-vs-done line, and today's tasks with checkboxes.
struct PlanPanel: View {
    let model: TodayModel
    let plan: PlanState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let next = plan.upNext {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: next.domain.symbol).foregroundStyle(next.domain.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.isNow ? "Now: \(next.title)" : "Up next: \(next.title)").fontWeight(.medium)
                        Text("\(next.times) · \(next.duration)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    Button("Start") { model.startPlanned(next.id) }
                    Button("Done as planned") { model.doneAsPlanned(next.id) }
                    Button("Skip") { model.skipPlanned(next.id) }
                }
            } else if plan.items.isEmpty {
                Text("Nothing planned. Type “plan 1400-1600 deep work” in Quick Entry, or stamp a template at Close the day.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let summary = plan.summary {
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            if !plan.tasks.isEmpty {
                Divider()
                ForEach(plan.tasks) { task in TaskRowView(task: task, model: model) }
            } else {
                Text("No tasks for today. Add one with “t write deck ~45m”.").font(.callout).foregroundStyle(.tertiary)
            }
        }
    }
}

/// A task with a checkbox, details, and a context menu for the usual moves.
struct TaskRowView: View {
    let task: PlanState.TaskItem
    let model: TodayModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                task.isDone ? model.reopenTask(task.id) : model.completeTask(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? Color.secondary : Domain.work.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark not done" : "Mark done")
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if task.priority > 0 { Text(String(repeating: "!", count: task.priority)).foregroundStyle(.secondary).fontWeight(.bold) }
                    Text(task.title).strikethrough(task.isDone).foregroundStyle(task.isDone ? .secondary : .primary)
                }
                if !task.detail.isEmpty {
                    Text(task.detail).font(.caption).foregroundStyle(task.isOverdue ? .orange : .secondary)
                }
            }
            Spacer()
            if !task.isDone {
                Button { model.startTask(task.id) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.borderless)
                    .help("Start a work timer for this task")
            }
        }
        .contextMenu {
            if !task.isDone {
                Button("Start timer") { model.startTask(task.id) }
                Button("Move to tomorrow") { model.moveToTomorrow(task.id) }
                Button("Someday") { model.somedayTask(task.id) }
                Button("Drop") { model.dropTask(task.id) }
            }
            Button("Delete", role: .destructive) { model.deleteTask(task.id) }
        }
    }
}

#Preview("Plan panel") {
    let model = PreviewSupport.todayModel()
    return VStack {
        if let state = model.state { PlanPanel(model: model, plan: state.plan) }
    }
    .padding()
    .frame(width: 640)
}
