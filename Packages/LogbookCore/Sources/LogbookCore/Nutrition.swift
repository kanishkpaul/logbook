import Foundation

/// What one serving or one log entry contains: energy, macros and the two
/// tracked stimulants.
///
/// `nil` means "not known", which is different from zero: an entry logged
/// without values has all-`nil` fields and is flagged *needs values*.
public struct Nutrition: Hashable, Sendable, Codable {
    public var kcal: Double?
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    public var caffeineMg: Double?
    public var nicotineMg: Double?

    public init(
        kcal: Double? = nil,
        proteinG: Double? = nil,
        carbsG: Double? = nil,
        fatG: Double? = nil,
        caffeineMg: Double? = nil,
        nicotineMg: Double? = nil
    ) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.caffeineMg = caffeineMg
        self.nicotineMg = nicotineMg
    }

    public static let zero = Nutrition(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, caffeineMg: 0, nicotineMg: 0)

    /// Every field, in display order, for code that treats them uniformly.
    public static var fields: [WritableKeyPath<Nutrition, Double?>] { [\.kcal, \.proteinG, \.carbsG, \.fatG, \.caffeineMg, \.nicotineMg] }

    /// True when no field is known.
    public var isEmpty: Bool { Self.fields.allSatisfy { self[keyPath: $0] == nil } }

    /// Scales every known field (e.g. 250 g of a 100 g serving → ×2.5).
    public func scaled(by factor: Double) -> Nutrition {
        var n = self
        for f in Self.fields { n[keyPath: f] = self[keyPath: f].map { $0 * factor } }
        return n
    }

    /// Field-wise sum. A field stays `nil` only when it is unknown on both sides.
    public static func + (a: Nutrition, b: Nutrition) -> Nutrition {
        var n = Nutrition()
        for f in fields {
            switch (a[keyPath: f], b[keyPath: f]) {
            case (nil, nil): n[keyPath: f] = nil
            case let (x, y): n[keyPath: f] = (x ?? 0) + (y ?? 0)
            }
        }
        return n
    }

    /// Fills fields that are unknown here from `other` (typed values win).
    public func filling(from other: Nutrition) -> Nutrition {
        var n = self
        for f in Self.fields where n[keyPath: f] == nil { n[keyPath: f] = other[keyPath: f] }
        return n
    }
}
