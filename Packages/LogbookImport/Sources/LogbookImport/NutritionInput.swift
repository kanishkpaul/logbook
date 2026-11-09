import Foundation
import LogbookCore

/// The shorthand values grammar for any text field that takes nutrition:
/// `350 / 14 / 0`, `408 60c 12f`, `1.2nic`, `~` for an estimate.
public enum NutritionInput {
    public static func parse(_ text: String) -> (nutrition: Nutrition, isEstimate: Bool)? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return ShorthandParser.values(t).map { (nutrition: $0.0, isEstimate: $0.1) }
    }
}
