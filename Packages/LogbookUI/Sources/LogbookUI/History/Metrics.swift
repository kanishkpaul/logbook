import Foundation
import LogbookCore
import LogbookPersistence

/// The daily metrics charts and Trends can show, read from `daily_facts`.
public struct MetricSpec: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let unit: String
    public let domain: Domain
    let value: @Sendable (DailyFacts) -> Double?
    let formatter: @Sendable (Double) -> String
    /// For your own metrics: the definition key; values come from the range's custom map.
    public var customKey: String?

    public func value(_ f: DailyFacts) -> Double? { value(f) }
    /// Minutes, shown as durations; axes tick on whole hours.
    public var isDuration: Bool { ["work", "sleep", "nc_min"].contains(id) }
    public func format(_ v: Double) -> String { formatter(v) }

    public static func == (a: MetricSpec, b: MetricSpec) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

public enum Metrics {
    static let duration: @Sendable (Double) -> String = { Durations.compact(minutes: Int($0.rounded())) }
    static let whole: @Sendable (Double) -> String = { NutritionFormat.whole($0) }
    static func unit(_ u: String, _ base: @escaping @Sendable (Double) -> String) -> @Sendable (Double) -> String {
        { "\(base($0)) \(u)" }
    }

    public static let work = MetricSpec(id: "work", title: "Work", unit: "", domain: .work, value: { $0.workMin.map(Double.init) }, formatter: duration)
    public static let sleep = MetricSpec(id: "sleep", title: "Sleep", unit: "", domain: .sleep, value: { $0.sleepMin.map(Double.init) }, formatter: duration)
    public static let kcal = MetricSpec(id: "kcal", title: "kcal in", unit: "kcal", domain: .food, value: { $0.kcal }, formatter: unit("kcal", whole))
    public static let protein = MetricSpec(id: "protein", title: "Protein", unit: "g", domain: .food, value: { $0.proteinG }, formatter: unit("g", whole))
    public static let carbs = MetricSpec(id: "carbs", title: "Carbs", unit: "g", domain: .food, value: { $0.carbsG }, formatter: unit("g", whole))
    public static let fat = MetricSpec(id: "fat", title: "Fat", unit: "g", domain: .food, value: { $0.fatG }, formatter: unit("g", whole))
    public static let caffeine = MetricSpec(id: "caffeine", title: "Caffeine", unit: "mg", domain: .caffeine, value: { $0.caffeineMg }, formatter: unit("mg", whole))
    public static let nicotine = MetricSpec(id: "nicotine", title: "Nicotine", unit: "mg", domain: .nicotine, value: { $0.nicotineMg }, formatter: unit("mg", { NutritionFormat.number($0) }))
    public static let burn = MetricSpec(id: "burn", title: "Logged burn", unit: "kcal", domain: .energy, value: { $0.burnKcal }, formatter: unit("kcal", whole))
    public static let steps = MetricSpec(id: "steps", title: "Steps", unit: "", domain: .energy, value: { $0.steps }, formatter: whole)
    public static let net = MetricSpec(id: "net", title: "Net kcal", unit: "kcal", domain: .food, value: { $0.netKcal }, formatter: unit("kcal", whole))
    public static let ncCount = MetricSpec(id: "nc_count", title: "Nature's call (count)", unit: "", domain: .natureCall, value: { $0.ncCount.map(Double.init) }, formatter: whole)
    public static let ncMinutes = MetricSpec(id: "nc_min", title: "Nature's call (time)", unit: "", domain: .natureCall, value: { $0.ncMin.map(Double.init) }, formatter: duration)

    public static let all = [work, sleep, kcal, protein, carbs, fat, caffeine, nicotine, burn, steps, net, ncCount, ncMinutes]

    public static func spec(_ id: String, custom: [MetricDefinition] = []) -> MetricSpec {
        all.first { $0.id == id } ?? custom.map(spec(for:)).first { $0.id == id } ?? work
    }

    /// A chartable spec for one of your own metrics.
    public static func spec(for def: MetricDefinition) -> MetricSpec {
        let unit = def.unit
        return MetricSpec(id: "custom.\(def.key)", title: unit.isEmpty ? def.name : "\(def.name) (\(unit))", unit: unit,
                          domain: .other, value: { _ in nil },
                          formatter: { v in unit.isEmpty ? NutritionFormat.number(v) : "\(NutritionFormat.number(v)) \(unit)" },
                          customKey: def.key)
    }
}

/// Ranges offered on history screens.
public enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
    case week = "7d", month = "28d", quarter = "3m", year = "1y"
    public var id: String { rawValue }
    public var days: Int {
        switch self {
        case .week: 7
        case .month: 28
        case .quarter: 91
        case .year: 365
        }
    }
}
