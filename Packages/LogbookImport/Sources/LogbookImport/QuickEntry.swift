import Foundation
import GRDB
import LogbookCore
import LogbookPersistence
import SQLiteData

/// One-line logging in the Notes shorthand, with a live preview.
///
/// Understands everything the importer does for "today" (`0945-1045 study`,
/// `pulao 250g`, `coffee`, `cig`, `nc 1550-1708`, `sleep 0045-0930`,
/// `burn 373 11773`, `steps 9000`) plus timer commands:
/// `start study`, `start sleep`, `start nc`, `stop`, `stop sleep`.
public struct QuickEntry: Sendable {
    public let store: LogStore

    public init(store: LogStore) {
        self.store = store
    }

    /// One row of the live preview.
    public struct PreviewLine: Hashable, Sendable {
        /// `work`, `sleep`, `nature_call`, `food`, `burn`, `steps`, `timer`, `dictionary`.
        public var kind: String
        public var title: String
        public var detail: String
    }

    public struct Interpretation: Sendable {
        public var text: String
        public var lines: [PreviewLine] = []
        /// Why this can't be saved, if it can't.
        public var problem: String?
        public var canCommit: Bool { problem == nil && action != nil }
        var action: Action?
    }

    enum Action: Sendable {
        case insert(blocks: [TimeBlock], foods: [FoodLogEntry], samples: [MetricSample], newFoods: [Food])
        case start(BlockKind, String)
        case stop(TimeBlock)
        case copy(from: LogicalDay, to: LogicalDay)
        case saveMeal(name: String, parts: [MealPart])
        case addTask(NewTask)
        case addPlan(kind: BlockKind, start: Date, end: Date, label: String, raw: String)
    }

    // MARK: Interpret

    public func interpret(_ raw: String) throws -> Interpretation {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = Interpretation(text: text)
        guard !text.isEmpty else { return out }
        let lower = text.lowercased()
        let now = store.now(), tz = store.timeZone()
        let today = store.boundary.logicalDay(containing: now, in: tz)

        if lower == "start" || lower.hasPrefix("start ") {
            let rest = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            let (kind, label) = Self.kindAndLabel(rest)
            if try store.runningBlocks().contains(where: { $0.kind == kind }) {
                out.problem = "A \(Self.name(kind)) timer is already running"
            }
            out.lines = [PreviewLine(kind: "timer", title: "Start \(Self.name(kind)) timer", detail: label.isEmpty ? "now" : "\(label) · now")]
            out.action = .start(kind, label)
            return out
        }

        if lower == "stop" || lower.hasPrefix("stop ") {
            let rest = String(text.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            let running = try store.runningBlocks()
            let target: TimeBlock?
            if rest.isEmpty {
                guard running.count <= 1 else {
                    out.problem = "Several timers are running; say “stop work”, “stop sleep” or “stop nc”"
                    return out
                }
                target = running.first
            } else {
                let kind = Self.kindAndLabel(rest).0
                target = running.first { $0.kind == kind }
            }
            guard let target else {
                out.problem = "No timer to stop"
                return out
            }
            let minutes = Durations.minutes(from: target.startUTC, to: max(now, target.startUTC))
            out.lines = [PreviewLine(kind: "timer", title: "Stop \(Self.name(target.kind)) timer",
                                     detail: [target.label, Durations.compact(minutes: minutes)].filter { !$0.isEmpty }.joined(separator: " · "))]
            out.action = .stop(target)
            return out
        }

        if lower.hasPrefix("t "), text.count > 2 {
            let t = PlanShorthand.task(String(text.dropFirst(2)), today: today)
            guard !t.title.isEmpty else { out.problem = "Give the task a title: t write deck ~45m fri"; return out }
            out.lines = [PreviewLine(kind: "task", title: t.title, detail: Self.taskDetail(t, today: today, tz: tz))]
            out.action = .addTask(NewTask(title: t.title, listName: t.listName, priority: t.priority, due: t.due,
                                          scheduled: t.scheduled, someday: t.someday, estimateMin: t.estimateMinutes,
                                          recurrence: t.recurrence, rawText: text))
            return out
        }

        if lower.hasPrefix("plan ") {
            guard let p = PlanShorthand.plan(String(text.dropFirst(5)), today: today) else {
                out.problem = "Plan needs times: plan 1400-1600 deep work"
                return out
            }
            let start = p.start.date(in: tz), end = p.end.date(in: tz)
            let fmt = Self.timeFormatter(tz)
            let dayText = p.day == today ? "today" : p.day == today.next ? "tomorrow" : Self.dayFormatter(tz).string(from: start)
            out.lines = [PreviewLine(kind: "plan", title: "Plan \(Self.name(p.kind))\(p.label.isEmpty ? "" : " · \(p.label)")",
                                     detail: "\(dayText) \(fmt.string(from: start))–\(fmt.string(from: end)) · \(Durations.compact(minutes: Durations.minutes(from: start, to: end)))")]
            out.action = .addPlan(kind: p.kind, start: start, end: end, label: p.label, raw: text)
            return out
        }

        if lower == "copy yesterday" {
            let n = try store.foodCount(on: today.previous)
            guard n > 0 else {
                out.problem = "Nothing was logged yesterday"
                return out
            }
            out.lines = [PreviewLine(kind: "food", title: "Copy yesterday's food", detail: "\(n) item\(n == 1 ? "" : "s") · same times today")]
            out.action = .copy(from: today.previous, to: today)
            return out
        }

        if lower.hasPrefix("meal "), let eq = text.firstIndex(of: "=") {
            try defineMeal(text, eq: eq, into: &out)
            return out
        }

        let parser = ShorthandParser(defaultYear: today.year)
        switch parser.parseLine(text, on: today) {
        case .issue(_, let message):
            out.problem = message
        case .entry(let entry):
            try interpret(entry, line: text, today: today, now: now, tz: tz, into: &out)
        }
        return out
    }

    private func interpret(_ entry: ParsedEntry, line: String, today: LogicalDay, now: Date, tz: TimeZone, into out: inout Interpretation) throws {
        let fmt = Self.timeFormatter(tz)
        switch entry {
        case .block(let b):
            let start = b.start.date(in: tz), end = b.end.date(in: tz)
            let block = try store.blockRow(kind: b.kind, start: start, end: end, label: b.label, timeZone: tz,
                                           isEstimate: b.isEstimate, source: .manual, rawText: line)
            let minutes = Durations.minutes(from: start, to: end)
            out.lines = [PreviewLine(kind: b.kind.rawValue, title: Self.name(b.kind).capitalized,
                                     detail: ["\(fmt.string(from: start))–\(fmt.string(from: end))", Durations.compact(minutes: minutes), b.label]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))]
            if end > now.addingTimeInterval(60) { out.problem = "That block ends in the future; use “start …” for a live timer" }
            out.action = .insert(blocks: [block], foods: [], samples: [], newFoods: [])

        case .food(let f):
            let at = f.timeMinutes.map { WallTime(day: today, minutes: $0).date(in: tz) } ?? now
            if f.nutrition == nil, let meal = try store.meals().first(where: { Self.matches($0, f.matchKey) }) {
                let times = f.unit == "x" ? (f.quantity ?? 1) : 1
                let rows = store.mealEntryRows(meal, times: times, consumedAt: at)
                let total = rows.reduce(Nutrition()) { $0 + $1.nutrition }
                out.lines = [PreviewLine(kind: "food", title: "Meal · \(meal.meal.name)\(times == 1 ? "" : " x\(NutritionFormat.number(times))")",
                                         detail: NutritionFormat.compact(total))]
                    + rows.map { PreviewLine(kind: "dictionary", title: $0.name, detail: NutritionFormat.compact($0.nutrition)) }
                out.action = .insert(blocks: [], foods: rows, samples: [], newFoods: [])
                return
            }
            var resolver = try store.database.read { db in
                FoodResolver(library: try LibraryIndex(db: db), dictionaryValuesAreEstimates: false)
            }
            let r = resolver.resolve(f, store: store, importBatchID: nil, newFoodID: store.uuid())
            let entry = store.foodEntryRow(name: f.name, food: r.food, servings: r.servings, quantity: f.quantity, unit: f.unit,
                                           nutrition: r.nutrition, consumedAt: at, timeZone: tz,
                                           isEstimate: r.isEstimate, source: .manual, rawText: line)
            var lines = [PreviewLine(kind: "food", title: f.name, detail: NutritionFormat.compact(entry.nutrition))]
            if let food = r.newFood {
                let serving = food.servingSize.map { "per \(NutritionFormat.number($0)) \(food.servingUnit ?? "")" } ?? "per serving"
                lines.append(PreviewLine(kind: "dictionary", title: "Add “\(food.name)” to the dictionary", detail: serving))
            } else if let food = r.food, f.nutrition == nil {
                lines.append(PreviewLine(kind: "dictionary", title: "From the dictionary: \(food.name)",
                                         detail: r.servings == 1 ? "1 serving" : "\(NutritionFormat.number(r.servings)) servings"))
            }
            out.lines = lines
            out.action = .insert(blocks: [], foods: [entry], samples: [], newFoods: r.newFood.map { [$0] } ?? [])

        case .burn(let kcal, let steps, let est):
            var samples: [MetricSample] = []
            var lines: [PreviewLine] = []
            try store.database.read { db in
                if let def = try LogStore.metricDefinition(key: "active_kcal", in: db) {
                    samples.append(store.metricSampleRow(metricID: def.id, value: kcal, day: today, isEstimate: est, rawText: line))
                    lines.append(PreviewLine(kind: "burn", title: "Burn", detail: "\(NutritionFormat.number(kcal)) kcal"))
                }
                if let steps, let def = try LogStore.metricDefinition(key: "steps", in: db) {
                    samples.append(store.metricSampleRow(metricID: def.id, value: steps, day: today, isEstimate: est, rawText: line))
                    lines.append(PreviewLine(kind: "steps", title: "Steps", detail: NutritionFormat.number(steps)))
                }
            }
            out.lines = lines
            out.action = .insert(blocks: [], foods: [], samples: samples, newFoods: [])

        case .steps(let value, let est):
            let def = try store.database.read { try LogStore.metricDefinition(key: "steps", in: $0) }
            guard let def else { out.problem = "No steps metric"; return }
            out.lines = [PreviewLine(kind: "steps", title: "Steps", detail: NutritionFormat.number(value))]
            out.action = .insert(blocks: [], foods: [], samples: [store.metricSampleRow(metricID: def.id, value: value, day: today, isEstimate: est, rawText: line)], newFoods: [])

        case .workTotal, .nutritionTotal:
            out.problem = "Totals are computed for you; log the blocks or foods instead"
        }
    }

    /// `meal breakfast = coffee + egg x2 + toast`: every part must be in the dictionary.
    private func defineMeal(_ text: String, eq: String.Index, into out: inout Interpretation) throws {
        let name = text[text.index(text.startIndex, offsetBy: 5)..<eq].trimmingCharacters(in: .whitespaces)
        let rhs = text[text.index(after: eq)...]
        guard !name.isEmpty else { out.problem = "Name the meal: meal breakfast = coffee + toast"; return }
        let library = try store.database.read { try LibraryIndex(db: $0) }
        var parts: [MealPart] = []
        for raw in rhs.split(separator: "+") {
            let f = ShorthandParser.food(raw.trimmingCharacters(in: .whitespaces))
            guard !f.name.isEmpty else { continue }
            guard let food = library.match(f.matchKey) else {
                out.problem = "“\(f.baseName)” isn't in the dictionary yet; log it once with values first"
                return
            }
            parts.append(MealPart(food: food, servings: FoodResolver.servings(quantity: f.quantity, unit: f.unit, of: food),
                                  quantity: f.quantity, unit: f.unit))
        }
        guard !parts.isEmpty else { out.problem = "List the items: meal \(name) = coffee + toast"; return }
        let exists = try store.meals().contains { $0.meal.name.lowercased() == name.lowercased() }
        let total = parts.reduce(Nutrition()) { $0 + $1.food.nutrition.scaled(by: $1.servings) }
        out.lines = [PreviewLine(kind: "dictionary", title: "\(exists ? "Replace" : "Save") meal “\(name)”", detail: NutritionFormat.compact(total))]
            + parts.map { PreviewLine(kind: "food", title: $0.food.name, detail: $0.servings == 1 ? "1 serving" : "\(NutritionFormat.number($0.servings)) servings") }
        out.action = .saveMeal(name: name, parts: parts)
    }

    static func matches(_ meal: MealDetail, _ key: String) -> Bool {
        ([meal.meal.name] + meal.meal.aliasList).contains { ParsedFood.matchKey($0) == key }
    }

    // MARK: Commit

    /// Saves what `interpret` previewed. Returns a short confirmation.
    @discardableResult
    public func commit(_ interpretation: Interpretation) throws -> String {
        guard interpretation.canCommit, let action = interpretation.action else {
            throw Failure.cannotCommit(interpretation.problem ?? "Nothing to save")
        }
        switch action {
        case .insert(let blocks, let foods, let samples, let newFoods):
            try store.database.write { db in
                for row in newFoods { try Food.insert { row }.execute(db) }
                for row in blocks { try TimeBlock.insert { row }.execute(db) }
                for row in foods { try FoodLogEntry.insert { row }.execute(db) }
                for row in samples { try MetricSample.insert { row }.execute(db) }
            }
            return "Logged " + interpretation.lines.filter { $0.kind != "dictionary" }.map(\.title).joined(separator: ", ")
        case .start(let kind, let label):
            try store.startBlock(kind: kind, label: label)
            return "Started \(Self.name(kind))"
        case .stop(let block):
            try store.stopBlock(id: block.id)
            return "Stopped \(Self.name(block.kind))"
        case .copy(let from, let to):
            let n = try store.copyFood(from: from, to: to).count
            return "Copied \(n) item\(n == 1 ? "" : "s") from yesterday"
        case .saveMeal(let name, let parts):
            try store.saveMeal(name: name, parts: parts)
            return "Saved meal \(name)"
        case .addTask(let task):
            try store.addTask(task)
            return "Added task \(task.title)"
        case .addPlan(let kind, let start, let end, let label, let raw):
            try store.addPlanBlock(kind: kind, start: start, end: end, label: label, rawText: raw)
            return "Planned \(Self.name(kind))"
        }
    }

    public enum Failure: Error, Equatable {
        case cannotCommit(String)
    }

    // MARK: Helpers

    /// `sleep`, `nc …`, `work …`, or anything else as a work label.
    static func kindAndLabel(_ rest: String) -> (BlockKind, String) {
        let lower = rest.lowercased()
        for (word, kind) in [("sleep", BlockKind.sleep), ("nc", .natureCall), ("work", .work)] {
            if lower == word { return (kind, "") }
            if lower.hasPrefix(word + " ") { return (kind, String(rest.dropFirst(word.count + 1)).trimmingCharacters(in: .whitespaces)) }
        }
        return (.work, rest)
    }

    static func name(_ kind: BlockKind) -> String {
        switch kind {
        case .work: "work"
        case .sleep: "sleep"
        case .natureCall: "nature's call"
        default: kind.rawValue
        }
    }

    static func dayFormatter(_ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = tz
        f.dateFormat = "EEE d MMM"
        return f
    }

    /// `~45m · !! · due Fri 13 Nov · #horizon · every Mon`.
    static func taskDetail(_ t: ParsedTask, today: LogicalDay, tz: TimeZone) -> String {
        func day(_ d: LogicalDay) -> String {
            d == today ? "today" : d == today.next ? "tomorrow"
                : dayFormatter(tz).string(from: DayBoundary.calendarDay.start(of: d, in: tz).addingTimeInterval(43_200))
        }
        var parts: [String] = []
        if let e = t.estimateMinutes { parts.append("~\(Durations.compact(minutes: e))") }
        if t.priority > 0 { parts.append(String(repeating: "!", count: t.priority)) }
        if let d = t.due { parts.append("due \(day(d))") }
        if let s = t.scheduled { parts.append("on \(day(s))") }
        if t.someday { parts.append("someday") }
        if let l = t.listName { parts.append("#\(l)") }
        if let r = t.recurrence { parts.append(r.summary) }
        return parts.isEmpty ? "inbox" : parts.joined(separator: " · ")
    }

    static func timeFormatter(_ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = tz
        f.dateFormat = "HH:mm"
        return f
    }
}
