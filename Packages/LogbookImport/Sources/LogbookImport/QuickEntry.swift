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
            var resolver = try store.database.read { db in
                FoodResolver(library: try LibraryIndex(db: db), dictionaryValuesAreEstimates: false)
            }
            let r = resolver.resolve(f, store: store, importBatchID: nil, newFoodID: store.uuid())
            let consumedAt = f.timeMinutes.map { WallTime(day: today, minutes: $0).date(in: tz) } ?? now
            let entry = store.foodEntryRow(name: f.name, food: r.food, servings: r.servings, quantity: f.quantity, unit: f.unit,
                                           nutrition: r.nutrition, consumedAt: consumedAt, timeZone: tz,
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

    static func timeFormatter(_ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = tz
        f.dateFormat = "HH:mm"
        return f
    }
}
