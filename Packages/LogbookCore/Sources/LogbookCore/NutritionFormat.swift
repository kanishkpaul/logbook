import Foundation

/// Text for nutrition values. Unknown fields are left out, never shown as 0.
public enum NutritionFormat {
    public struct Part: Hashable, Sendable {
        public let label: String
        public let value: String
        public let unit: String
    }

    /// Known fields in display order: kcal, protein, carbs, fat, caffeine, nicotine.
    public static func parts(_ n: Nutrition) -> [Part] {
        var out: [Part] = []
        if let v = n.kcal { out.append(Part(label: "kcal", value: whole(v), unit: "kcal")) }
        if let v = n.proteinG { out.append(Part(label: "protein", value: number(v), unit: "g")) }
        if let v = n.carbsG { out.append(Part(label: "carbs", value: number(v), unit: "g")) }
        if let v = n.fatG { out.append(Part(label: "fat", value: number(v), unit: "g")) }
        if let v = n.caffeineMg { out.append(Part(label: "caffeine", value: number(v), unit: "mg")) }
        if let v = n.nicotineMg { out.append(Part(label: "nicotine", value: number(v), unit: "mg")) }
        return out
    }

    /// `408 kcal · 8 g protein · 60 g carbs`, or `needs values`.
    public static func summary(_ n: Nutrition) -> String {
        let p = parts(n)
        guard !p.isEmpty else { return "needs values" }
        return p.map { $0.label == "kcal" ? "\($0.value) kcal" : "\($0.value) \($0.unit) \($0.label)" }.joined(separator: " · ")
    }

    /// Dense one-liner for lists: `490 kcal · P 10 · C 74 · F 14 · 110 mg caffeine`.
    /// Macros under 10 g keep one decimal; caffeine and nicotine appear only
    /// when non-zero; unknown fields are left out.
    public static func compact(_ n: Nutrition) -> String {
        guard !n.isEmpty else { return "needs values" }
        var out: [String] = []
        if let v = n.kcal { out.append("\(whole(v)) kcal") }
        if let v = n.proteinG { out.append("P \(grams(v))") }
        if let v = n.carbsG { out.append("C \(grams(v))") }
        if let v = n.fatG { out.append("F \(grams(v))") }
        if let v = n.caffeineMg, v > 0 { out.append("\(whole(v)) mg caffeine") }
        if let v = n.nicotineMg, v > 0 { out.append("\(number(v)) mg nicotine") }
        return out.isEmpty ? "0 kcal" : out.joined(separator: " · ")
    }

    public static func whole(_ v: Double) -> String { String(Int(v.rounded())) }

    static func grams(_ v: Double) -> String { v < 10 ? number(v) : whole(v) }

    /// Whole numbers without decimals; otherwise one decimal (`489.6`, `1.2`).
    public static func number(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }
}
