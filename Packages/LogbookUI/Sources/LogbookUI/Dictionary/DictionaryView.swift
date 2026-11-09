import LogbookCore
import LogbookImport
import LogbookPersistence
import SwiftUI

/// The dictionary: everything you eat (and smoke), with serving and macros.
/// Logging a name uses these values; editing never changes past entries.
public struct DictionaryView: View {
    @Bindable var model: DictionaryModel
    @State private var selection: UUID?

    public init(model: DictionaryModel) {
        self.model = model
    }

    public var body: some View {
        Table(model.visible, selection: $selection) {
            TableColumn("Name") { f in
                HStack(spacing: 4) {
                    if f.isFavourite { Image(systemName: "star.fill").foregroundStyle(.yellow).imageScale(.small) }
                    Text(f.name).foregroundStyle(f.archivedAt == nil ? .primary : .secondary)
                }
            }
            TableColumn("Serving") { f in Text(DictionaryModel.servingText(f)).foregroundStyle(.secondary) }
                .width(90)
            TableColumn("kcal") { f in num(f.kcal) }.width(55)
            TableColumn("Protein") { f in num(f.proteinG, "g") }.width(60)
            TableColumn("Carbs") { f in num(f.carbsG, "g") }.width(60)
            TableColumn("Fat") { f in num(f.fatG, "g") }.width(55)
            TableColumn("Caffeine") { f in num(f.caffeineMg, "mg") }.width(70)
            TableColumn("Nicotine") { f in num(f.nicotineMg, "mg") }.width(70)
        }
        .searchable(text: $model.search, prompt: "Name or alias")
        .inspector(isPresented: .constant(true)) {
            Group {
                if let food = model.food(selection) {
                    FoodEditor(food: food, model: model).id(food.id)
                } else {
                    ContentUnavailableView("Select an entry", systemImage: "book",
                                           description: Text("Or add one with +. Typing a food with values in Quick Entry also adds it."))
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 320)
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $model.showArchived) { Label("Show archived", systemImage: "archivebox") }
                Button { selection = model.add() } label: { Label("Add", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .navigationTitle("Dictionary")
        .onAppear { model.reload() }
    }

    private func num(_ v: Double?, _ unit: String = "") -> some View {
        Text(v.map { NutritionFormat.number($0) + (unit.isEmpty ? "" : " \(unit)") } ?? "—")
            .monospacedDigit()
            .foregroundStyle(v == nil ? .tertiary : .primary)
    }
}

/// Edits one dictionary entry; saves on every committed field.
struct FoodEditor: View {
    @State var food: Food
    let model: DictionaryModel
    @State private var aliases = ""

    init(food: Food, model: DictionaryModel) {
        _food = State(initialValue: food)
        self.model = model
        _aliases = State(initialValue: food.aliasList.joined(separator: ", "))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $food.name).onSubmit(save)
                TextField("Aliases (comma-separated)", text: $aliases).onSubmit(save)
                Toggle("Favourite", isOn: $food.isFavourite).onChange(of: food.isFavourite) { save() }
            }
            Section("Serving") {
                HStack {
                    TextField("Size", value: $food.servingSize, format: .number).onSubmit(save)
                    TextField("Unit", text: Binding(get: { food.servingUnit ?? "" }, set: { food.servingUnit = $0.isEmpty ? nil : $0 }))
                        .onSubmit(save)
                }
                Text("Logging “\(food.name) 2x” or a quantity in the same unit scales these values.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Per serving") {
                field("kcal", \.kcal)
                field("Protein (g)", \.proteinG)
                field("Carbs (g)", \.carbsG)
                field("Fat (g)", \.fatG)
                field("Caffeine (mg)", \.caffeineMg)
                field("Nicotine (mg)", \.nicotineMg)
            }
            Section {
                Button(food.archivedAt == nil ? "Archive" : "Unarchive") {
                    model.setArchived(food.id, food.archivedAt == nil)
                }
                Text("Archived entries are hidden and no longer matched by name. Past entries keep their values.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func field(_ title: String, _ keyPath: WritableKeyPath<Nutrition, Double?>) -> some View {
        TextField(title, value: Binding(
            get: { food.nutrition[keyPath: keyPath] },
            set: { food.nutrition[keyPath: keyPath] = $0 }
        ), format: .number)
        .onSubmit(save)
    }

    private func save() {
        food.aliasList = aliases.split(separator: ",").map(String.init)
        model.save(food)
    }
}

#Preview("Dictionary") {
    NavigationStack {
        DictionaryView(model: DictionaryModel(store: PreviewSupport.store()))
    }
    .frame(width: 1000, height: 600)
}
