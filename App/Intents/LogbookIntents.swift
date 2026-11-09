import AppIntents
import Foundation
import LogbookCore
import LogbookImport
import LogbookPersistence
import LogbookUI

// Actions for Shortcuts, Spotlight and Siri. They run in the app (launched in
// the background if needed) and write through the same Quick Entry / LogStore
// paths as the app, so the same rules and validation apply.

nonisolated enum LogbookIntentError: Error, CustomLocalizedStringResourceConvertible {
    case cannotLog(String)
    case nothingRunning

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .cannotLog(let reason): "\(reason)"
        case .nothingRunning: "No timer is running."
        }
    }
}

/// "Log in Logbook": anything Quick Entry understands.
struct LogIntent: AppIntent {
    static let title: LocalizedStringResource = "Log in Logbook"
    static let description = IntentDescription(
        "Log in your Notes shorthand: “0945-1045 study”, “pulao 250g”, “coffee”, “burn 373 11773”, “weight 71.2”, “t write deck ~45m fri”, “plan 1400-1600 deep work”.")

    @Parameter(title: "Entry", requestValueDialog: "What should I log?")
    var text: String

    @AppDependency var store: LogStore

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$text)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let q = QuickEntry(store: store)
        let i = try q.interpret(text)
        guard i.canCommit else { throw LogbookIntentError.cannotLog(i.problem ?? "I couldn't read “\(text)”.") }
        let message = try q.commit(i)
        return .result(value: message, dialog: "\(message).")
    }
}

nonisolated enum TimerKind: String, AppEnum {
    case work, sleep, natureCall

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Timer"
    static let caseDisplayRepresentations: [TimerKind: DisplayRepresentation] = [
        .work: "Work", .sleep: "Sleep", .natureCall: "Nature's call",
    ]

    var kind: BlockKind {
        switch self {
        case .work: .work
        case .sleep: .sleep
        case .natureCall: .natureCall
        }
    }
}

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a timer"
    static let description = IntentDescription("Starts a work, sleep or nature's-call timer in Logbook.")

    @Parameter(title: "Timer", default: .work) var kind: TimerKind
    @Parameter(title: "Label") var label: String?
    @AppDependency var store: LogStore

    static var parameterSummary: some ParameterSummary { Summary("Start \(\.$kind) timer") { \.$label } }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try store.startBlock(kind: kind.kind, label: label ?? "")
        return .result(dialog: "Started \(kind.rawValue == "natureCall" ? "nature's call" : kind.rawValue).")
    }
}

struct StopTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop timers"
    static let description = IntentDescription("Stops a running timer in Logbook (or all of them).")

    @Parameter(title: "Timer") var kind: TimerKind?
    @AppDependency var store: LogStore

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let running = try store.runningBlocks().filter { kind == nil || $0.kind == kind!.kind }
        guard !running.isEmpty else { throw LogbookIntentError.nothingRunning }
        var parts: [String] = []
        for b in running {
            let stopped = try store.stopBlock(id: b.id)
            parts.append("\(b.label.isEmpty ? b.kind.rawValue.replacingOccurrences(of: "_", with: " ") : b.label) \(Durations.compact(minutes: Durations.minutes(from: stopped.startUTC, to: stopped.endUTC!)))")
        }
        return .result(dialog: "Stopped \(parts.joined(separator: ", ")).")
    }
}

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a task"
    static let description = IntentDescription("Adds a task to Logbook.")

    @Parameter(title: "Title") var title: String
    @Parameter(title: "Due") var due: Date?
    @Parameter(title: "Estimate (minutes)") var estimate: Int?
    @Parameter(title: "List") var list: String?
    @AppDependency var store: LogStore

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$title)") { \.$due; \.$estimate; \.$list } }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let day = due.map { store.boundary.logicalDay(containing: $0, in: store.timeZone()) }
        try store.addTask(NewTask(title: title, listName: list, due: day, estimateMin: estimate, rawText: "shortcut: \(title)"))
        return .result(dialog: "Added “\(title)”.")
    }
}

/// A dictionary entry, for "Log food" with autocomplete.
nonisolated struct FoodEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Food"
    static let defaultQuery = FoodQuery()
    let id: UUID
    let name: String
    let summary: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }
}

struct FoodQuery: EntityStringQuery {
    @AppDependency var store: LogStore

    func entities(for identifiers: [UUID]) async throws -> [FoodEntity] {
        try store.dictionary(includeArchived: true).filter { identifiers.contains($0.id) }.map(Self.entity)
    }

    func entities(matching string: String) async throws -> [FoodEntity] {
        let q = string.lowercased()
        return try store.dictionary().filter { f in
            f.name.lowercased().contains(q) || f.aliasList.contains { $0.lowercased().contains(q) }
        }.map(Self.entity)
    }

    func suggestedEntities() async throws -> [FoodEntity] {
        try store.dictionary().prefix(20).map(Self.entity)
    }

    static func entity(_ f: Food) -> FoodEntity {
        FoodEntity(id: f.id, name: f.name, summary: NutritionFormat.compact(f.nutrition))
    }
}

struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log food"
    static let description = IntentDescription("Logs something from your Logbook dictionary, with all its macros.")

    @Parameter(title: "Food") var food: FoodEntity
    @Parameter(title: "Servings", default: 1) var servings: Double
    @AppDependency var store: LogStore

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$servings) × \(\.$food)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let f = try store.dictionary(includeArchived: true).first(where: { $0.id == food.id }) else {
            throw LogbookIntentError.cannotLog("That food isn't in the dictionary any more.")
        }
        let entry = try store.logFood(name: servings == 1 ? f.name : "\(f.name) x\(NutritionFormat.number(servings))",
                                      food: f, servings: servings, rawText: "shortcut: \(f.name)")
        return .result(dialog: "Logged \(f.name): \(NutritionFormat.compact(entry.nutrition)).")
    }
}

/// "How's my day in Logbook?": the same numbers as the Today screen.
struct TodaySummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Today so far"
    static let description = IntentDescription("Work, sleep, food, caffeine and running timers for today.")
    @AppDependency var store: LogStore

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let tz = store.timeZone()
        let day = store.boundary.logicalDay(containing: store.now(), in: tz)
        let state = TodayPresenter(timeZone: tz).present(try store.snapshot(of: day, in: tz), now: store.now())
        var lines = state.heroes.filter { $0.value != "—" }.map { "\($0.title): \($0.value)\($0.unit.isEmpty ? "" : " \($0.unit)")" }
        lines += state.running.map { "Running: \($0.title)" }
        let text = lines.isEmpty ? "Nothing logged yet today." : lines.joined(separator: ". ") + "."
        return .result(value: text, dialog: "\(text)")
    }
}

/// Phrases for Siri and Spotlight. Each must name the app.
nonisolated struct LogbookShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogIntent(), phrases: ["Log in \(.applicationName)", "Add to \(.applicationName)"],
                    shortTitle: "Log", systemImageName: "text.cursor")
        AppShortcut(intent: StartTimerIntent(), phrases: ["Start \(\.$kind) in \(.applicationName)", "Start a timer in \(.applicationName)"],
                    shortTitle: "Start timer", systemImageName: "play.circle")
        AppShortcut(intent: StopTimerIntent(), phrases: ["Stop timer in \(.applicationName)", "Stop \(\.$kind) in \(.applicationName)"],
                    shortTitle: "Stop timer", systemImageName: "stop.circle")
        AppShortcut(intent: AddTaskIntent(), phrases: ["Add a task in \(.applicationName)"],
                    shortTitle: "Add task", systemImageName: "checklist")
        AppShortcut(intent: LogFoodIntent(), phrases: ["Log \(\.$food) in \(.applicationName)", "Log food in \(.applicationName)"],
                    shortTitle: "Log food", systemImageName: "fork.knife")
        AppShortcut(intent: TodaySummaryIntent(), phrases: ["How's my day in \(.applicationName)", "Today in \(.applicationName)"],
                    shortTitle: "Today so far", systemImageName: "sun.max")
    }
}
