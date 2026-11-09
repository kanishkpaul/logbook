import Foundation

/// kcal / protein / caffeine for one serving or one log entry.
///
/// `nil` means "not known", which is different from zero: a food logged
/// without values has `nil` fields and is flagged *needs values*.
public struct Nutrition: Hashable, Sendable, Codable {
    public var kcal: Double?
    public var proteinG: Double?
    public var caffeineMg: Double?

    public init(kcal: Double? = nil, proteinG: Double? = nil, caffeineMg: Double? = nil) {
        self.kcal = kcal
        self.proteinG = proteinG
        self.caffeineMg = caffeineMg
    }

    public static let zero = Nutrition(kcal: 0, proteinG: 0, caffeineMg: 0)

    /// True when no field is known.
    public var isEmpty: Bool { kcal == nil && proteinG == nil && caffeineMg == nil }

    /// Scales every known field (e.g. 250 g of a 100 g serving → ×2.5).
    public func scaled(by factor: Double) -> Nutrition {
        Nutrition(
            kcal: kcal.map { $0 * factor },
            proteinG: proteinG.map { $0 * factor },
            caffeineMg: caffeineMg.map { $0 * factor }
        )
    }
}
