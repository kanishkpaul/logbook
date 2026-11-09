import LogbookCore
import LogbookPersistence
import SwiftUI

/// The main window: a sidebar of screens, the ⌘K palette and Close the day.
public struct RootView<Diagnostics: View>: View {
    let today: TodayModel
    let dictionary: DictionaryModel
    let data: DataModel
    @Bindable var router: AppRouter
    let openQuickEntry: () -> Void
    let diagnostics: Diagnostics
    @State private var calendar: CalendarModel
    @State private var tasks: TasksModel
    @State private var workHistory: HistoryModel
    @State private var sleepHistory: HistoryModel
    @State private var bodyHistory: HistoryModel
    @State private var trendsHistory: HistoryModel
    @State private var review: ReviewModel

    public init(today: TodayModel, dictionary: DictionaryModel, data: DataModel, router: AppRouter,
                openQuickEntry: @escaping () -> Void = {}, @ViewBuilder diagnostics: () -> Diagnostics) {
        self.today = today
        self.dictionary = dictionary
        self.data = data
        self.router = router
        self.openQuickEntry = openQuickEntry
        _calendar = State(initialValue: CalendarModel(store: today.store))
        _tasks = State(initialValue: TasksModel(store: today.store, actions: today))
        _workHistory = State(initialValue: HistoryModel(store: today.store))
        _sleepHistory = State(initialValue: HistoryModel(store: today.store))
        _bodyHistory = State(initialValue: HistoryModel(store: today.store))
        _trendsHistory = State(initialValue: HistoryModel(store: today.store, range: .quarter))
        _review = State(initialValue: ReviewModel(store: today.store))
        self.diagnostics = diagnostics()
    }

    private var selection: Binding<RootScreen?> {
        Binding(get: { router.screen }, set: { if let s = $0 { router.screen = s } })
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                section(nil, [.today, .tasks, .calendar])
                section("History", [.review, .work, .sleep, .body, .trends])
                section("Library", [.dictionary, .metrics, .importing, .data, .diagnostics])
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } detail: {
            switch router.screen {
            case .today: TodayView(model: today, closingDay: $router.showingCloseDay) { router.go($0) }
            case .tasks: TasksView(model: tasks)
            case .calendar: CalendarView(model: calendar)
            case .review: ReviewView(model: review, insights: today.insights, writer: today.recaps)
            case .work: WorkView(model: workHistory)
            case .sleep: SleepView(model: sleepHistory)
            case .body: BodyView(model: bodyHistory)
            case .trends: TrendsView(model: trendsHistory)
            case .dictionary: DictionaryView(model: dictionary)
            case .importing: ImportView(store: today.store)
            case .data: DataView(model: data)
            case .diagnostics: diagnostics
            case .metrics: MetricsView(store: today.store)
            }
        }
        .frame(minWidth: 960, minHeight: 680)
        .sheet(isPresented: $router.showingPalette) {
            CommandPalette(commands: commands) { router.showingPalette = false }
        }
    }

    @ViewBuilder
    private func section(_ title: String?, _ screens: [RootScreen]) -> some View {
        Section {
            ForEach(screens, id: \.self) { s in
                Label(s.title, systemImage: s.symbol)
                    .help(s.shortcutDigit.map { "\(s.title) (⌘\($0))" } ?? s.title)
            }
        } header: {
            if let title { Text(title) }
        }
    }

    /// Everything the palette offers. Screens first, then actions.
    var commands: [PaletteCommand] {
        var list = RootScreen.allCases.map { s in
            PaletteCommand(id: "go-\(s.rawValue)", title: "Go to \(s.title)", symbol: s.symbol,
                           shortcut: s.shortcutDigit.map { "⌘\($0)" }) { router.go(s) }
        }
        list += [
            PaletteCommand(id: "quick-entry", title: "Quick Entry", symbol: "text.cursor", shortcut: "⌘L", run: openQuickEntry),
            PaletteCommand(id: "close-day", title: "Close the day", symbol: "moon.zzz", shortcut: "⇧⌘D") { router.closeTheDay() },
            PaletteCommand(id: "start-work", title: "Start work timer", symbol: Domain.work.symbol) { today.startTimer(.work) },
            PaletteCommand(id: "start-sleep", title: "Start sleep timer", symbol: Domain.sleep.symbol) { today.startTimer(.sleep) },
            PaletteCommand(id: "start-nc", title: "Start nature's call timer", symbol: Domain.natureCall.symbol) { today.startTimer(.natureCall) },
            PaletteCommand(id: "stop-all", title: "Stop all timers", symbol: "stop.circle", shortcut: "⌘.") {
                for t in today.state?.running ?? [] { today.stopTimer(t.id) }
            },
            PaletteCommand(id: "copy-yesterday", title: "Copy yesterday's food", symbol: "arrow.uturn.down") { today.submit("copy yesterday") },
            PaletteCommand(id: "back-up", title: "Back up now", symbol: "externaldrive.badge.checkmark") { data.backUpNow(); router.go(.data) },
            PaletteCommand(id: "export-json", title: "Export JSON", symbol: "square.and.arrow.up") { data.exportJSON() },
            PaletteCommand(id: "export-csv", title: "Export CSV", symbol: "tablecells") { data.exportCSV() },
            PaletteCommand(id: "calendar-week", title: "Calendar: this week", symbol: "calendar") {
                router.go(.calendar); calendar.mode = .week; calendar.goToToday()
            },
            PaletteCommand(id: "calendar-month", title: "Calendar: this month", symbol: "calendar") {
                router.go(.calendar); calendar.mode = .month; calendar.goToToday()
            },
            PaletteCommand(id: "refresh-insights", title: "Refresh insights", symbol: "sparkle.magnifyingglass") { today.refreshInsights(force: true) },
        ]
        for (i, t) in (today.state?.plan.tasks.filter { !$0.isDone } ?? []).prefix(5).enumerated() {
            list.append(PaletteCommand(id: "task-\(i)", title: "Start task: \(t.title)", symbol: "play.fill") { today.startTask(t.id) })
        }
        return list
    }
}

#Preview("Root") {
    let store = PreviewSupport.store()
    let today = TodayModel(store: store)
    today.start()
    return RootView(today: today, dictionary: DictionaryModel(store: store),
                    data: DataModel(store: store, backups: Backups(database: store.database, directory: FileManager.default.temporaryDirectory.appending(path: "logbook-preview-backups"))),
                    router: AppRouter()) { Text("Diagnostics") }
        .frame(width: 1100, height: 800)
}
