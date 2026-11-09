import Foundation
import LogbookCore
import LogbookPersistence
import Observation

/// The dictionary of things you eat (and smoke): every entry with its serving
/// and full macros. Log entries copy these values when written, so editing
/// here never changes history.
@Observable
public final class DictionaryModel {
    public let store: LogStore
    public private(set) var foods: [Food] = []
    public var search = ""
    public var showArchived = false { didSet { reload() } }
    public var lastError: String?

    public init(store: LogStore) {
        self.store = store
        reload()
    }

    /// Entries matching `search` by name or alias.
    public var visible: [Food] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return foods }
        return foods.filter { f in
            f.name.lowercased().contains(q) || f.aliasList.contains { $0.lowercased().contains(q) }
        }
    }

    public func reload() {
        do {
            foods = try store.dictionary(includeArchived: showArchived)
        } catch {
            lastError = "\(error)"
        }
    }

    /// Creates and saves an empty entry; returns its id for selection.
    @discardableResult
    public func add(name: String = "New food") -> UUID? {
        do {
            let food = try store.saveFood(store.newFood(name: name))
            reload()
            return food.id
        } catch {
            lastError = "\(error)"
            return nil
        }
    }

    public func save(_ food: Food) {
        do {
            try store.saveFood(food)
            reload()
        } catch {
            lastError = "\(error)"
        }
    }

    public func setArchived(_ id: UUID, _ archived: Bool) {
        do {
            try store.archiveFood(id: id, archived: archived)
            reload()
        } catch {
            lastError = "\(error)"
        }
    }

    public func food(_ id: UUID?) -> Food? {
        foods.first { $0.id == id }
    }

    /// "per 250 g", "per serving".
    public static func servingText(_ food: Food) -> String {
        guard let size = food.servingSize else { return "per serving" }
        return "per \(NutritionFormat.number(size)) \(food.servingUnit ?? "")".trimmingCharacters(in: .whitespaces)
    }
}
