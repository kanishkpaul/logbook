import LogbookCore
import LogbookPersistence
import SwiftUI

/// Saved meals and what's in them. Meals are defined in Quick Entry:
/// `meal breakfast = coffee + 2 eggs + toast 2 slices`, then logged by name.
struct MealsView: View {
    let store: LogStore
    @State private var meals: [MealDetail] = []
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Text("Define a meal in Quick Entry: “meal breakfast = coffee + 2 eggs + toast 2 slices”. Then type “breakfast” (or “breakfast x2”) to log every item at once. Redefining a meal replaces it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(meals) { meal in
                Section {
                    ForEach(meal.items, id: \.item.id) { item in
                        HStack {
                            Text(item.label)
                            Spacer()
                            Text(NutritionFormat.compact(item.nutrition)).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text(meal.meal.name).font(.headline)
                        Text(NutritionFormat.compact(meal.nutrition)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Delete", role: .destructive) { archive(meal.id) }.buttonStyle(.borderless)
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        meals = (try? store.meals()) ?? []
    }

    private func archive(_ id: UUID) {
        do {
            try store.archiveMeal(id: id)
            reload()
        } catch {
            self.error = "\(error)"
        }
    }
}

#Preview("Meals") {
    MealsView(store: PreviewSupport.store())
        .frame(width: 600, height: 400)
}
