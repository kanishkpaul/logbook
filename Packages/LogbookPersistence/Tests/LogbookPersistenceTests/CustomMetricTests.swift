import Foundation
import LogbookCore
import Testing
@testable import LogbookPersistence

@Suite struct CustomMetricTests {
    let env = TestEnv(start: Date(timeIntervalSince1970: 0))

    @Test func defineArchiveAndKeys() throws {
        env.set(env.at(2026, 11, 9, 9, 0))
        let s = try env.store()
        let w = try s.addMetric(name: "Body weight", unit: "kg", aggregation: .last)
        #expect(w.key == "body_weight" && !w.isBuiltin)
        #expect(throws: LogStore.MetricError.nameTaken("body weight")) { try s.addMetric(name: "body weight") }
        #expect(throws: LogStore.MetricError.nameTaken("Steps")) { try s.addMetric(name: "Steps") }
        #expect(throws: LogStore.MetricError.emptyName) { try s.addMetric(name: "  ") }
        #expect(try s.customMetric(named: "BODY WEIGHT")?.id == w.id)
        let steps = try #require(try s.metricDefinitions().first { $0.key == "steps" })
        #expect(throws: LogStore.MetricError.builtin) { try s.archiveMetric(id: steps.id) }
        try s.archiveMetric(id: w.id)
        #expect(try s.customMetric(named: "body weight") == nil)
        #expect(try s.metricDefinitions().map(\.key) == ["active_kcal", "steps"])
    }

    @Test func rangeCarriesCustomValuesByTheirAggregation() throws {
        env.set(env.at(2026, 11, 9, 8, 0))
        let s = try env.store()
        try s.addMetric(name: "Weight", unit: "kg", aggregation: .last)
        try s.addMetric(name: "Water", unit: "ml", aggregation: .sum)
        try s.recordMetric(key: "weight", value: 71.4)
        try s.recordMetric(key: "water", value: 500)
        env.set(env.at(2026, 11, 9, 20, 0))
        try s.recordMetric(key: "weight", value: 71.0)
        try s.recordMetric(key: "water", value: 750)
        let day = LogicalDay("2026-11-09")!
        let r = try s.range(day, through: day, in: env.tz)
        #expect(r.customDefinitions.map(\.name) == ["Water", "Weight"])
        #expect(r.custom["weight"]?[day] == 71.0 && r.custom["water"]?[day] == 1250)
        let c = try s.insightContext(days: 3)
        #expect(c.metricNames["custom.weight"] == "Weight (kg)")
        #expect(c.series("custom.water").last == 1250)
    }
}
