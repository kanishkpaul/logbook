import LogbookCore
import LogbookPersistence
import Observation
import SwiftUI

/// All tasks, live: smart views and lists.
@Observable
public final class TasksModel {
    public let store: LogStore
    public let actions: TodayModel
    public var view: TaskView = .today { didSet { present() } }
    public private(set) var state: TasksState?
    @ObservationIgnored private var rows: [TaskRow] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(store: LogStore, actions: TodayModel) {
        self.store = store
        self.actions = actions
    }

    var today: LogicalDay { store.boundary.logicalDay(containing: store.now(), in: store.timeZone()) }

    public func start() {
        guard task == nil else { return }
        let stream = store.observeTasks(doneSince: store.now().addingTimeInterval(-30 * 86_400))
        task = Task { [weak self] in
            do {
                for try await rows in stream {
                    self?.rows = rows
                    self?.present()
                }
            } catch {
                self?.actions.lastError = "\(error)"
            }
        }
    }

    private func present() {
        state = TasksPresenter(timeZone: store.timeZone()).present(rows, view: view, today: today)
    }
}

public struct TasksView: View {
    @Bindable var model: TasksModel
    @State private var text = ""

    public init(model: TasksModel) {
        self.model = model
    }

    private var smart: [TaskView] { [.inbox, .today, .upcoming, .anytime, .someday, .done] }

    public var body: some View {
        HSplitView {
            List(selection: Binding(get: { model.view }, set: { if let v = $0 { model.view = v } })) {
                Section {
                    ForEach(smart, id: \.self) { v in row(v) }
                }
                if let lists = model.state?.lists, !lists.isEmpty {
                    Section("Lists") {
                        ForEach(lists, id: \.self) { row(.list($0)) }
                    }
                }
            }
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "plus.circle").foregroundStyle(.secondary)
                    TextField("write SIH deck ~45m !! fri #horizon every mon", text: $text)
                        .textFieldStyle(.plain)
                        .onSubmit(add)
                }
                .padding(10)
                .background(.background.secondary, in: .rect(cornerRadius: 10))
                if let preview = model.actions.interpret("t " + text), !text.isEmpty {
                    Text(preview.lines.first.map { "\($0.title) · \($0.detail)" } ?? preview.problem ?? "")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(model.state?.sections ?? []) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title).font(.headline)
                                ForEach(section.tasks) { TaskRowView(task: $0, model: model.actions) }
                            }
                        }
                        if model.state?.sections.isEmpty ?? true {
                            ContentUnavailableView("Nothing here", systemImage: model.view.symbol)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .navigationTitle(model.view.title)
        .onAppear { model.start() }
    }

    private func row(_ v: TaskView) -> some View {
        HStack {
            Label(v.title, systemImage: v.symbol)
            Spacer()
            if let n = model.state?.counts[v], n > 0, v != .done {
                Text("\(n)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .tag(v)
    }

    /// New tasks go where you're looking: Today → today, a list → that list.
    private func add() {
        var line = text.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        switch model.view {
        case .today where !line.contains("@"): line += " @today"
        case .someday: line += " @someday"
        case .list(let name) where !line.contains("#"): line += " #\(name)"
        default: break
        }
        if model.actions.submit("t " + line) { text = "" }
    }
}

#Preview("Tasks") {
    let store = PreviewSupport.store()
    let today = TodayModel(store: store)
    let model = TasksModel(store: store, actions: today)
    model.start()
    return NavigationStack { TasksView(model: model) }.frame(width: 900, height: 600)
}
