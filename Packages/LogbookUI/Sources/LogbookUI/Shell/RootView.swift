import LogbookPersistence
import SwiftUI

/// The main window: a sidebar of screens. More screens arrive in later milestones.
public struct RootView<Diagnostics: View>: View {
    public enum Screen: String, Hashable, CaseIterable {
        case today, dictionary, importing, data, diagnostics

        var title: String {
            switch self {
            case .today: "Today"
            case .dictionary: "Dictionary"
            case .importing: "Import"
            case .data: "Backups & Export"
            case .diagnostics: "Diagnostics"
            }
        }

        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .dictionary: "book"
            case .importing: "square.and.arrow.down"
            case .data: "externaldrive"
            case .diagnostics: "stethoscope"
            }
        }
    }

    let today: TodayModel
    let dictionary: DictionaryModel
    let data: DataModel
    let diagnostics: Diagnostics
    /// Reopens on the screen you last used.
    @AppStorage("selectedScreen") private var screen: Screen = .today

    private var selection: Binding<Screen?> {
        Binding(get: { screen }, set: { if let s = $0 { screen = s } })
    }

    public init(today: TodayModel, dictionary: DictionaryModel, data: DataModel, @ViewBuilder diagnostics: () -> Diagnostics) {
        self.today = today
        self.dictionary = dictionary
        self.data = data
        self.diagnostics = diagnostics()
    }

    public var body: some View {
        NavigationSplitView {
            List(Screen.allCases, id: \.self, selection: selection) { s in
                Label(s.title, systemImage: s.symbol)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            switch screen {
            case .today: TodayView(model: today)
            case .dictionary: DictionaryView(model: dictionary)
            case .importing: ImportView(store: today.store)
            case .data: DataView(model: data)
            case .diagnostics: diagnostics
            }
        }
        .frame(minWidth: 960, minHeight: 680)
    }
}

#Preview("Root") {
    let store = PreviewSupport.store()
    let today = TodayModel(store: store)
    today.start()
    return RootView(today: today, dictionary: DictionaryModel(store: store),
                    data: DataModel(store: store, backups: Backups(database: store.database, directory: FileManager.default.temporaryDirectory.appending(path: "logbook-preview-backups")))) { Text("Diagnostics") }
        .frame(width: 1100, height: 800)
}
