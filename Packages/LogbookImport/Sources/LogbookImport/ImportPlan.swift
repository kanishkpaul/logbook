import CryptoKit
import Foundation
import GRDB
import LogbookCore
import LogbookPersistence
import SQLiteData

/// Everything an import would write, computed without writing: the preview.
public struct ImportPlan: Sendable {
    public var batch: ImportBatch
    public var newFoods: [Food] = []
    public var blocks: [TimeBlock] = []
    public var foodEntries: [FoodLogEntry] = []
    public var samples: [MetricSample] = []
    public var issues: [ImportIssue] = []
    public var days: [DaySummary] = []
    /// Rows whose deterministic id already exists (imported before).
    public var alreadyImported = 0

    public struct DaySummary: Hashable, Sendable {
        public var day: LogicalDay
        public var blocks = 0
        public var foods = 0
        public var samples = 0
        public var workMin = 0
        public var kcal: Double = 0
    }

    public var rowCount: Int { blocks.count + foodEntries.count + samples.count }
    public var isEmpty: Bool { rowCount == 0 && newFoods.isEmpty }
    public var errors: [ImportIssue] { issues.filter { $0.severity == .error } }
    public var warnings: [ImportIssue] { issues.filter { $0.severity == .warning } }
}

/// Turns a parsed document into an `ImportPlan` against the current database.
public struct ImportPlanner: Sendable {
    public let store: LogStore
    public var timeZone: TimeZone

    public init(store: LogStore, timeZone: TimeZone) {
        self.store = store
        self.timeZone = timeZone
    }

    public func plan(_ doc: ParsedDocument, sourceName: String) throws -> ImportPlan {
        let batch = store.importBatchRow(sourceName: sourceName, lineCount: doc.lineCount)
        var plan = ImportPlan(batch: batch, issues: doc.issues)

        try store.database.read { db in
            var resolver = FoodResolver(library: try LibraryIndex(db: db), dictionaryValuesAreEstimates: true)
            guard let stepsDef = try LogStore.metricDefinition(key: "steps", in: db),
                  let burnDef = try LogStore.metricDefinition(key: "active_kcal", in: db)
            else { throw LogStore.Failure.unknownMetric("steps/active_kcal") }

            for day in doc.days {
                var summary = ImportPlan.DaySummary(day: day.date)
                var occurrences: [String: Int] = [:]
                var typedWork: [(Int, SourceLine)] = []
                var typedTotals: [(Nutrition, SourceLine)] = []
                var intake = Nutrition()
                var burn: Double?

                func stableID(_ line: SourceLine, _ part: String = "") -> UUID {
                    let key = "\(day.date)|\(line.text)|\(part)"
                    let n = occurrences[key, default: 0]
                    occurrences[key] = n + 1
                    return Self.stableUUID("logbook-import|\(key)|\(n)")
                }
                func issue(_ severity: ImportIssue.Severity, _ code: ImportIssue.Code, _ line: SourceLine, _ message: String) {
                    plan.issues.append(.init(severity: severity, code: code, line: line.number, day: day.date, message: message))
                }
                func exists(_: TimeBlock.Type, _ id: UUID) throws -> Bool { try TimeBlock.find(id).fetchCount(db) > 0 }
                func exists(_: FoodLogEntry.Type, _ id: UUID) throws -> Bool { try FoodLogEntry.find(id).fetchCount(db) > 0 }
                func exists(_: MetricSample.Type, _ id: UUID) throws -> Bool { try MetricSample.find(id).fetchCount(db) > 0 }
                func exists(_: Food.Type, _ id: UUID) throws -> Bool { try Food.find(id).fetchCount(db) > 0 }

                for parsed in day.lines {
                    let line = parsed.line
                    switch parsed.entry {
                    case .block(let b):
                        let id = stableID(line)
                        let start = b.start.date(in: timeZone), end = b.end.date(in: timeZone)
                        let minutes = Durations.minutes(from: start, to: end)
                        if let typed = b.typedMinutes, typed != minutes {
                            issue(.warning, .typedDurationMismatch, line,
                                  "typed [\(Durations.compact(minutes: typed))] but the times give \(Durations.compact(minutes: minutes))")
                        }
                        if b.kind == .work { summary.workMin += minutes }
                        if try exists(TimeBlock.self, id) { plan.alreadyImported += 1; continue }
                        if try Self.manualDuplicate(kind: b.kind, start: start, end: end, in: db) {
                            issue(.warning, .likelyDuplicate, line, "a \(b.kind) block with the same times is already logged; skipped")
                            continue
                        }
                        plan.blocks.append(try store.blockRow(
                            kind: b.kind, start: start, end: end, label: b.label, timeZone: timeZone,
                            isEstimate: b.isEstimate, source: .import, rawText: line.text,
                            importBatchID: batch.id, id: id
                        ))
                        summary.blocks += 1

                    case .food(let f):
                        let id = stableID(line)
                        let consumedAt = WallTime(day: day.date, minutes: f.timeMinutes ?? 12 * 60).date(in: timeZone)
                        var r = resolver.resolve(f, store: store, importBatchID: batch.id,
                                                 newFoodID: Self.stableUUID("logbook-import|food|\(f.matchKey)"))
                        if let new = r.newFood {
                            if try exists(Food.self, new.id) {
                                // Seeded by an earlier run of this file: use it, don't recreate it.
                                r.food = try Food.find(new.id).fetchOne(db)
                            } else {
                                plan.newFoods.append(new)
                            }
                        }
                        switch r.note {
                        case .valuesFromLibrary?:
                            issue(.info, .valuesFromLibrary, line, "values for “\(f.name)” taken from the dictionary (estimate)")
                        case .needsValues?:
                            issue(.info, .needsValues, line, "“\(f.name)” has no values yet")
                        default: break
                        }
                        intake = intake + (r.nutrition ?? Nutrition())
                        summary.kcal += r.nutrition?.kcal ?? 0
                        if try exists(FoodLogEntry.self, id) { plan.alreadyImported += 1; continue }
                        plan.foodEntries.append(store.foodEntryRow(
                            name: f.name, food: r.food, servings: r.servings, quantity: f.quantity, unit: f.unit,
                            nutrition: r.nutrition, consumedAt: consumedAt, timeZone: timeZone,
                            isEstimate: r.isEstimate, source: .import, rawText: line.text,
                            importBatchID: batch.id, id: id
                        ))
                        summary.foods += 1

                    case .burn(let kcal, let steps, let est):
                        burn = (burn ?? 0) + kcal
                        var pairs: [(MetricDefinition, Double, String)] = [(burnDef, kcal, "burn")]
                        if let steps { pairs.append((stepsDef, steps, "steps")) }
                        for (def, value, part) in pairs {
                            let id = stableID(line, part)
                            if try exists(MetricSample.self, id) { plan.alreadyImported += 1; continue }
                            plan.samples.append(store.metricSampleRow(
                                metricID: def.id, value: value, day: day.date, isEstimate: est, source: .import,
                                rawText: line.text, importBatchID: batch.id, id: id
                            ))
                            summary.samples += 1
                        }

                    case .steps(let value, let est):
                        let id = stableID(line)
                        if try exists(MetricSample.self, id) { plan.alreadyImported += 1; continue }
                        plan.samples.append(store.metricSampleRow(
                            metricID: stepsDef.id, value: value, day: day.date, isEstimate: est, source: .import,
                            rawText: line.text, importBatchID: batch.id, id: id
                        ))
                        summary.samples += 1

                    case .workTotal(let minutes):
                        typedWork.append((minutes, line))

                    case .nutritionTotal(let n):
                        typedTotals.append((n, line))
                    }
                }

                // Typed totals are checks, never sources.
                for (typed, line) in typedWork where typed != summary.workMin {
                    issue(.warning, .workTotalMismatch, line,
                          "typed $ \(Durations.compact(minutes: typed)) but the work blocks add up to \(Durations.compact(minutes: summary.workMin))")
                }
                for (typed, line) in typedTotals {
                    var net = intake
                    net.kcal = (intake.kcal ?? 0) - (burn ?? 0)
                    if !Self.close(typed, intake) && !(burn != nil && Self.close(typed, net)) {
                        issue(.warning, .nutritionTotalMismatch, line,
                              "typed $ \(Self.format(typed)) but the foods add up to \(Self.format(intake))"
                                + (burn != nil ? " (net \(Self.format(net)))" : ""))
                    }
                }
                plan.days.append(summary)
            }
        }
        plan.issues.sort { ($0.line ?? 0) < ($1.line ?? 0) }
        return plan
    }

    // MARK: Helpers

    /// A UUID derived from `key` (SHA-256, formatted as a version-5-style UUID),
    /// so re-importing the same line yields the same id.
    public static func stableUUID(_ key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func manualDuplicate(kind: BlockKind, start: Date, end: Date, in db: Database) throws -> Bool {
        try TimeBlock.where {
            $0.kind.eq(kind) && $0.startUTC.eq(start) && $0.endUTC.eq(end)
                && $0.deletedAt.is(nil) && $0.importBatchID.is(nil)
        }.fetchCount(db) > 0
    }

    /// Typed totals are rounded by hand; within 1 unit counts as a match.
    /// Only the fields the total line gave are compared.
    static func close(_ typed: Nutrition, _ computed: Nutrition) -> Bool {
        Nutrition.fields.allSatisfy { f in
            guard let a = typed[keyPath: f] else { return true }
            return abs(a - (computed[keyPath: f] ?? 0)) <= 1
        }
    }

    static func format(_ n: Nutrition) -> String {
        NutritionFormat.summary(n)
    }
}
