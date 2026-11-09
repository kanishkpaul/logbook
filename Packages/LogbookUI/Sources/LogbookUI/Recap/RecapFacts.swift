import Foundation
import LogbookCore

/// Picks the facts a recap may mention. All values come from presenters.
public enum RecapFacts {
    public static func daily(_ s: TodayState, insights: [Insight]) -> [RecapFact] {
        var facts: [RecapFact] = []
        func hero(_ id: String, _ label: String) {
            guard let h = s.heroes.first(where: { $0.id == id }), h.value != "—" else { return }
            facts.append(RecapFact(id: id, label: label, value: h.value + (h.unit.isEmpty ? "" : " \(h.unit)"), comparison: h.headline))
        }
        hero("work", "work today")
        hero("sleep", "last night's sleep")
        if let h = s.heroes.first(where: { $0.id == "kcal" }), h.value != "—" {
            facts.append(RecapFact(id: "kcal", label: h.title == "Net kcal" ? "net energy after logged burn" : "energy eaten",
                                   value: "\(h.value) kcal", comparison: h.headline.map { $0.replacingOccurrences(of: "intake ", with: "") }))
        }
        hero("protein", "protein")
        if let c = s.foodTotals.first(where: { $0.label == "caffeine" }), c.value != "0" {
            facts.append(RecapFact(id: "caffeine", label: "caffeine today", value: "\(c.value) mg"))
        }
        if let n = s.foodTotals.first(where: { $0.label == "nicotine" }), n.value != "0" {
            facts.append(RecapFact(id: "nicotine", label: "nicotine today", value: "\(n.value) mg"))
        }
        let tasks = s.plan.tasks
        if !tasks.isEmpty {
            facts.append(RecapFact(id: "tasks", label: "tasks done", value: "\(tasks.filter(\.isDone).count) of \(tasks.count)"))
        }
        if let top = insights.first {
            facts.append(RecapFact(id: "noticed", label: "a pattern the app noticed", value: top.title))
        }
        return Array(facts.prefix(10))
    }
}
