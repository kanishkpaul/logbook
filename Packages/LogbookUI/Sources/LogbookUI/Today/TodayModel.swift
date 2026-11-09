import Foundation
import LogbookCore
import LogbookImport
import LogbookPersistence
import Observation

/// Live state for Today, the menu bar and Quick Entry.
///
/// Observes the database for the current logical day, re-presents on every
/// change and every 30 s (so running totals move), and rolls over at the day
/// boundary. Writes go through `LogStore` / `QuickEntry`.
@Observable
public final class TodayModel {
    public let store: LogStore
    public let quickEntry: QuickEntry
    public private(set) var state: TodayState?
    public private(set) var snapshot: DaySnapshot?
    public var lastError: String?
    /// Short confirmation after a Quick Entry save ("Logged pulao 250g").
    public private(set) var lastConfirmation: String?
    /// One-click foods: favourites, then frequent recents.
    public private(set) var quickAdd: [String] = []
    /// Food entries logged yesterday (for "Copy yesterday").
    public private(set) var yesterdayFoodCount = 0
    /// True until the first thing is logged (and the welcome isn't dismissed).
    public private(set) var showWelcome = false
    /// Up to three insight cards (deterministic; see LogbookCore/Detectors).
    public private(set) var insights: [Insight] = []
    @ObservationIgnored private var insightsComputedAt: Date?
    @ObservationIgnored public var engine = InsightEngine()
    /// Writes the daily and weekly recaps (on-device model, template fallback).
    public let recaps = RecapWriter()

    public var caffeineHalfLifeHours: Double {
        didSet { UserDefaults.standard.set(caffeineHalfLifeHours, forKey: "caffeineHalfLifeHours"); represent() }
    }
    /// Which notification kinds are on (all on by default).
    public var enabledNotifications: Set<NotificationKind> {
        didSet { UserDefaults.standard.set(enabledNotifications.map(\.rawValue), forKey: "enabledNotifications") }
    }

    public var nicotineHalfLifeHours: Double {
        didSet { UserDefaults.standard.set(nicotineHalfLifeHours, forKey: "nicotineHalfLifeHours"); represent() }
    }

    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    public init(store: LogStore) {
        self.store = store
        self.quickEntry = QuickEntry(store: store)
        let d = UserDefaults.standard
        caffeineHalfLifeHours = d.object(forKey: "caffeineHalfLifeHours") as? Double ?? 5
        nicotineHalfLifeHours = d.object(forKey: "nicotineHalfLifeHours") as? Double ?? 2
        enabledNotifications = (d.array(forKey: "enabledNotifications") as? [String]).map { Set($0.compactMap(NotificationKind.init)) }
            ?? Set(NotificationKind.allCases)
    }

    public var currentDay: LogicalDay {
        store.boundary.logicalDay(containing: store.now(), in: store.timeZone())
    }

    /// Show a fixed day instead of today (the Calendar's day view). `nil` = follow today.
    public var pinnedDay: LogicalDay? {
        didSet {
            guard pinnedDay != oldValue, observation != nil else { return }
            observe(pinnedDay ?? currentDay)
        }
    }

    /// Starts observing (idempotent). Call once from the app.
    public func start() {
        guard observation == nil else { return }
        observe(pinnedDay ?? currentDay)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.tick()
            }
        }
    }

    public func stop() {
        observation?.cancel()
        ticker?.cancel()
        observation = nil
        ticker = nil
    }

    private func observe(_ day: LogicalDay) {
        observation?.cancel()
        let stream = store.observe(day, in: store.timeZone())
        observation = Task { [weak self] in
            do {
                for try await snapshot in stream {
                    self?.snapshot = snapshot
                    self?.represent()
                }
            } catch {
                self?.lastError = "Couldn't read the log: \(error)"
            }
        }
    }

    private func tick() {
        if pinnedDay == nil, let snapshot, snapshot.day != currentDay {
            observe(currentDay)
        } else {
            represent()
        }
    }

    private func represent() {
        guard let snapshot else { return }
        let presenter = TodayPresenter(
            timeZone: store.timeZone(),
            caffeine: HalfLifeModel(halfLife: max(0.5, caffeineHalfLifeHours) * 3600),
            nicotine: HalfLifeModel(halfLife: max(0.25, nicotineHalfLifeHours) * 3600)
        )
        state = presenter.present(snapshot, now: store.now())
        showWelcome = !UserDefaults.standard.bool(forKey: "welcomeDismissed") && !((try? store.hasAnyLogs()) ?? true)
        quickAdd = (try? store.quickAddNames()) ?? []
        yesterdayFoodCount = (try? store.foodCount(on: snapshot.day.previous)) ?? 0
        refreshInsights()
    }

    /// Recomputes insight cards at most once a minute (the engine runs
    /// permutation tests, so not on every 30-second tick).
    public func refreshInsights(force: Bool = false) {
        guard pinnedDay == nil else { return }
        let now = store.now()
        if !force, let last = insightsComputedAt, now.timeIntervalSince(last) < 60 { return }
        insightsComputedAt = now
        do {
            let context = try store.insightContext()
            insights = engine.run(context, memory: try store.insightMemory())
            try store.markShown(insights)
        } catch {
            lastError = "Insights: \(error)"
        }
    }

    public func dismissWelcome() {
        UserDefaults.standard.set(true, forKey: "welcomeDismissed")
        showWelcome = false
    }

    public func dismissInsight(_ insight: Insight) {
        run { try store.dismiss(insight) }
        refreshInsights(force: true)
    }

    public func snoozeInsight(_ insight: Insight) {
        run { try store.snooze(insight, days: 7) }
        refreshInsights(force: true)
    }

    public func insightFeedback(_ insight: Insight, _ value: String) {
        run { try store.feedback(insight, value) }
        if value == "wrong" { refreshInsights(force: true) }
    }

    // MARK: Actions

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    public func startTimer(_ kind: BlockKind, label: String = "") {
        run { try store.startBlock(kind: kind, label: label) }
    }

    public func stopTimer(_ id: UUID) {
        run { try store.stopBlock(id: id) }
    }

    public func stopTimer(_ id: UUID, at end: Date) {
        run { try store.stopBlock(id: id, at: end) }
    }

    public func discardBlock(_ id: UUID) {
        run { try store.deleteBlock(id: id) }
    }

    public func deleteFood(_ id: UUID) {
        run { try store.deleteFoodEntry(id: id) }
    }

    public func deleteSample(_ id: UUID) {
        run { try store.deleteSample(id: id) }
    }

    public func fillValues(_ id: UUID, nutrition: Nutrition, isEstimate: Bool) {
        run { try store.updateFoodEntry(id: id, nutrition: nutrition, isEstimate: isEstimate) }
    }

    public func recordMetric(_ key: String, value: Double) {
        run { try store.recordMetric(key: key, value: value, day: currentDay) }
    }

    // MARK: Tasks and plan

    public func completeTask(_ id: UUID) { run { try store.completeTask(id: id) } }
    public func reopenTask(_ id: UUID) { run { try store.reopenTask(id: id) } }
    public func dropTask(_ id: UUID) { run { try store.dropTask(id: id) } }
    public func deleteTask(_ id: UUID) { run { try store.deleteTask(id: id) } }
    public func startTask(_ id: UUID) { run { try store.startTask(id: id) } }
    public func moveTask(_ id: UUID, to day: LogicalDay?) { run { try store.scheduleTask(id: id, day: day) } }
    public func somedayTask(_ id: UUID) { run { try store.scheduleTask(id: id, day: nil, someday: true) } }
    public func moveToTomorrow(_ id: UUID) { moveTask(id, to: currentDay.next) }

    public func startPlanned(_ id: UUID) { run { try store.startPlanned(id: id) } }
    public func doneAsPlanned(_ id: UUID) { run { try store.completeAsPlanned(id: id) } }
    public func skipPlanned(_ id: UUID) { run { try store.setPlanStatus(id: id, .skipped) } }
    public func deletePlanned(_ id: UUID) { run { try store.deletePlanBlock(id: id) } }

    public var templates: [PlanTemplate] { (try? store.templates()) ?? [] }

    public func saveTemplate(named name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        run { try store.saveTemplate(name: name, from: snapshot?.day ?? currentDay) }
    }

    /// Stamps a template onto tomorrow ("plan tomorrow").
    public func stampTomorrow(_ templateID: UUID) {
        run { try store.stamp(templateID: templateID, on: (snapshot?.day ?? currentDay).next) }
        lastConfirmation = "Planned tomorrow"
    }

    /// Everything the notification planner needs, read now.
    public func notificationInputs() throws -> NotificationInputs? {
        guard let snapshot, pinnedDay == nil else { return nil }
        let tz = store.timeZone(), now = store.now()
        let tomorrow = try store.snapshot(of: snapshot.day.next, in: tz)
        let due = try store.taskRows().map(\.task).filter {
            $0.status == .open && ($0.dueDay == snapshot.day || $0.dueDay == snapshot.day.next)
        }
        return NotificationInputs(now: now, timeZone: tz, today: snapshot, tomorrowPlans: tomorrow.plans, dueTasks: due,
                                  insights: insights, log: try store.notificationLog(since: now.addingTimeInterval(-14 * 86_400)),
                                  enabled: enabledNotifications)
    }

    /// Live preview for Quick Entry text.
    public func interpret(_ text: String) -> QuickEntry.Interpretation? {
        try? quickEntry.interpret(text)
    }

    /// Saves Quick Entry text. Returns true when something was saved.
    @discardableResult
    public func submit(_ text: String) -> Bool {
        do {
            let i = try quickEntry.interpret(text)
            lastConfirmation = try quickEntry.commit(i)
            lastError = nil
            return true
        } catch QuickEntry.Failure.cannotCommit(let reason) {
            lastError = reason
        } catch {
            lastError = "\(error)"
        }
        return false
    }

    /// Running timers that look forgotten (for the guard on launch and wake).
    public func forgottenTimers() -> [TodayState.RunningTimer] {
        represent()
        return state?.running.filter(\.looksForgotten) ?? []
    }
}
