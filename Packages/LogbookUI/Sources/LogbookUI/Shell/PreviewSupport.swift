import Foundation
import LogbookCore
import LogbookPersistence

/// Synthetic data for `#Preview`s only (never real logs): an in-memory
/// database with a plausible day ending around now.
public enum PreviewSupport {
    public static func store() -> LogStore {
        let db = try! AppDatabase.openInMemory()
        let store = LogStore(database: db)
        let cal = Calendar.gregorian(in: .current)
        let today = cal.startOfDay(for: Date())
        func at(_ h: Double, _ dayOffset: Int = 0) -> Date {
            cal.date(byAdding: .day, value: dayOffset, to: today)!.addingTimeInterval(h * 3600)
        }
        do {
            var pulao = store.newFood(name: "pulao")
            pulao.servingSize = 250
            pulao.servingUnit = "g"
            pulao.nutrition = Nutrition(kcal: 408, proteinG: 8, carbsG: 62, fatG: 12, caffeineMg: 0, nicotineMg: 0)
            try store.saveFood(pulao)
            var coffee = store.newFood(name: "coffee")
            coffee.nutrition = Nutrition(kcal: 40, proteinG: 1, carbsG: 5, fatG: 1, caffeineMg: 110, nicotineMg: 0)
            coffee.isFavourite = true
            try store.saveFood(coffee)
            var cig = store.newFood(name: "cigarette")
            cig.aliasList = ["cig"]
            cig.nutrition = Nutrition(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, caffeineMg: 0, nicotineMg: 1.2)
            try store.saveFood(cig)

            for d in -20 ... -1 where d % 5 != 0 {
                try store.addBlock(kind: .work, start: at(10, d), end: at(10 + 4 + Double(abs(d) % 4), d))
                try store.addBlock(kind: .sleep, start: at(1, d), end: at(8.5, d))
                try store.logFood(name: "pulao", food: pulao, consumedAt: at(13, d))
            }
            try store.addBlock(kind: .sleep, start: at(-0.75), end: at(8.25))
            try store.addBlock(kind: .work, start: at(9.5), end: at(12), label: "study")
            try store.addBlock(kind: .natureCall, start: at(12.2), end: at(12.4))
            try store.logFood(name: "coffee", food: coffee, consumedAt: at(9.6))
            try store.logFood(name: "pulao 300g", food: pulao, servings: 1.2, quantity: 300, unit: "g", consumedAt: at(13))
            try store.logFood(name: "cig", food: cig, consumedAt: at(14))
            try store.logFood(name: "Chicken roll", consumedAt: at(16))
            try store.recordMetric(key: "steps", value: 7400)
            if Date() > at(15) { try store.startBlock(kind: .work, label: "deep work") }
        } catch {
            print("preview seed failed: \(error)")
        }
        return store
    }

    public static func todayModel() -> TodayModel {
        let model = TodayModel(store: store())
        model.start()
        return model
    }
}
