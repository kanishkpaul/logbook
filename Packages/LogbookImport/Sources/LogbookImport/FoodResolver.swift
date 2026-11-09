import Foundation
import GRDB
import LogbookCore
import LogbookPersistence
import SQLiteData

/// Decides what a parsed food line logs, using the dictionary.
///
/// Shared by the importer and Quick Entry so both follow the same rules:
/// - typed values win; fields the line didn't give are filled from the
///   dictionary entry (scaled by quantity) so macros are always counted;
/// - a food typed with values that isn't in the dictionary yet is added to it
///   (unless the values are estimates);
/// - a name without values takes the dictionary's values;
/// - otherwise the entry *needs values*.
struct FoodResolver {
    var library: LibraryIndex
    /// Dictionary entries created earlier in the same run, by match key.
    var pending: [String: Food] = [:]
    /// Whether values taken purely from the dictionary are marked `~`
    /// (true for history, where the portion is unknown).
    var dictionaryValuesAreEstimates: Bool

    struct Resolution {
        var food: Food?
        var nutrition: Nutrition?
        var servings: Double
        var isEstimate: Bool
        /// A dictionary entry to create alongside the log entry.
        var newFood: Food?
        var note: ImportIssue.Code?
    }

    mutating func resolve(_ f: ParsedFood, store: LogStore, importBatchID: UUID?, newFoodID: UUID) -> Resolution {
        let known = library.match(f.matchKey) ?? pending[f.matchKey]
        let servings = known.map { Self.servings(quantity: f.quantity, unit: f.unit, of: $0) } ?? 1

        if let typed = f.nutrition {
            if let known {
                return Resolution(food: known, nutrition: typed.filling(from: known.nutrition.scaled(by: servings)),
                                  servings: servings, isEstimate: f.isEstimate, newFood: nil, note: nil)
            }
            var newFood: Food?
            if !f.isEstimate {
                let food = store.foodRow(name: f.baseName, nutrition: typed, servingSize: f.quantity,
                                         servingUnit: f.unit == "x" ? nil : f.unit,
                                         importBatchID: importBatchID, id: newFoodID)
                pending[f.matchKey] = food
                newFood = food
            }
            return Resolution(food: newFood, nutrition: typed, servings: 1, isEstimate: f.isEstimate, newFood: newFood, note: nil)
        }
        if let known, !known.nutrition.isEmpty {
            return Resolution(food: known, nutrition: known.nutrition.scaled(by: servings), servings: servings,
                              isEstimate: f.isEstimate || dictionaryValuesAreEstimates, newFood: nil, note: .valuesFromLibrary)
        }
        return Resolution(food: known, nutrition: nil, servings: 1, isEstimate: f.isEstimate, newFood: nil, note: .needsValues)
    }

    /// Servings of a dictionary entry for a logged quantity: `x2` doubles it;
    /// `300g` of a 250 g serving is 1.2; other units don't convert (1 serving).
    static func servings(quantity: Double?, unit: String?, of food: Food) -> Double {
        guard let quantity else { return 1 }
        if unit == "x" { return quantity }
        guard let size = food.servingSize, size > 0, unit != nil, unit == food.servingUnit else { return 1 }
        return quantity / size
    }
}

/// Dictionary entries by lowercased name and aliases (archived ones excluded).
struct LibraryIndex {
    var byKey: [String: Food] = [:]

    init(db: Database) throws {
        for food in try Food.where({ $0.archivedAt.is(nil) }).fetchAll(db) {
            for key in [food.name] + food.aliasList {
                let k = ParsedFood.matchKey(key)
                if byKey[k] == nil { byKey[k] = food }
            }
        }
    }

    func match(_ key: String) -> Food? { byKey[key] }
}
