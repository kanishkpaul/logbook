import LogbookPersistence
import SwiftUI

/// The main window: a sidebar of screens. More screens arrive in later milestones.
public struct RootView<Diagnostics: View>: View {
    public enum Screen: String, Hashable, CaseIterable {
        case today, calendar, tasks, work, sleep, body, trends, review, dictionary, importing, data, diagnostics

        var title: String {
            switch self {
            case .today: "Today"
            case .calendar: "Calendar"
            case .tasks: "Tasks"
            case .work: "Work"
            case .sleep: "Sleep"
            case .body: "Body"
            case .trends: "Trends"
            case .review: "Review"
            case .dictionary: "Dictionary"
            case .importing: "Import"
            case .data: "Backups & Export"
            case .diagnostics: "Diagnostics"
            }
        }

        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .calendar: "calendar"
            case .tasks: "checklist"
            case .work: Domain.work.symbol
            case .sleep: Domain.sleep.symbol
            case .body: "figure.walk"
            case .trends: "chart.xyaxis.line"
            case .review: "doc.text.magnifyingglass"
            case .dictionary: "book"
            case .importing: "square.and.arrow.down"
            case .data: "externaldrive"
            case .diagnostics: "stethoscope"
            }
        }
    }

    let today: TodayModel
    let dictionary: DictionaryModel
    let data: DataModel
    let diagnostics: Diagnostics
    @State private var calendar: CalendarModel
    @State private var tasks: TasksModel
    @State private var workHistory: HistoryModel
    @State private var sleepHistory: HistoryModel
    @State private var bodyHistory: HistoryModel
    @State private var trendsHistory: HistoryModel
    @State private var review: ReviewModel
    /// Reopens on the screen you last used.
    @AppStorage("selectedScreen") private var screen: Screen = .today

    private var selection: Binding<Screen?> {
        Binding(get: { screen }, set: { if let s = $0 { screen = s } })
    }

    public init(today: TodayModel, dictionary: DictionaryModel, data: DataModel, @ViewBuilder diagnostics: () -> Diagnostics) {
        self.today = today
        self.dictionary = dictionary
        self.data = data
        _calendar = State(initialValue: CalendarModel(store: today.store))
        _tasks = State(initialValue: TasksModel(store: today.store, actions: today))
        _workHistory = State(initialValue: HistoryModel(store: today.store))
        _sleepHistory = State(initialValue: HistoryModel(store: today.store))
        _bodyHistory = State(initialValue: HistoryModel(store: today.store))
        _trendsHistory = State(initialValue: HistoryModel(store: today.store, range: .quarter))
        _review = State(initialValue: ReviewModel(store: today.store))
        self.diagnostics = diagnostics()
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section {
                    ForEach([Screen.today, .tasks, .calendar], id: \.self) { Label($0.title, systemImage: $0.symbol) }
                }
                Section("History") {
                    ForEach([Screen.review, .work, .sleep, .body, .trends], id: \.self) { Label($0.title, systemImage: $0.symbol) }
                }
                Section("Library") {
                    ForEach([Screen.dictionary, .importing, .data, .diagnostics], id: \.self) { Label($0.title, systemImage: $0.symbol) }
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            switch screen {
            case .today: TodayView(model: today)
            case .calendar: CalendarView(model: calendar)
            case .tasks: TasksView(model: tasks)
            case .work: WorkView(model: workHistory)
            case .sleep: SleepView(model: sleepHistory)
            case .body: BodyView(model: bodyHistory)
            case .trends: TrendsView(model: trendsHistory)
            case .review: ReviewView(model: review, insights: today.insights)
            case .dictionary: DictionaryView(model: dictionary)
            case .importing: ImportView(store: today.store)
            case .data: DataView(model: data)
            case .diagnostics: diagnostics
            }
        }
        .frame(minWidth: 960, minHeight: 680)
    }
}

#Preview("Root") {
    let store = PreviewSupport.store()
    let today = TodayModel(store: store)
    today.start()
    return RootView(today: today, dictionary: DictionaryModel(store: store),
                    data: DataModel(store: store, backups: Backups(database: store.database, directory: FileManager.default.temporaryDirectory.appending(path: "logbook-preview-backups")))) { Text("Diagnostics") }
        .frame(width: 1100, height: 800)
}
