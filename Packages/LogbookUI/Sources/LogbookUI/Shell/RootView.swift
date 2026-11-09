import SwiftUI

/// The main window: a sidebar of screens. More screens arrive in later milestones.
public struct RootView<Diagnostics: View>: View {
    public enum Screen: String, Hashable, CaseIterable {
        case today, dictionary, importing, diagnostics

        var title: String {
            switch self {
            case .today: "Today"
            case .dictionary: "Dictionary"
            case .importing: "Import"
            case .diagnostics: "Diagnostics"
            }
        }

        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .dictionary: "book"
            case .importing: "square.and.arrow.down"
            case .diagnostics: "stethoscope"
            }
        }
    }

    let today: TodayModel
    let dictionary: DictionaryModel
    let diagnostics: Diagnostics
    /// Reopens on the screen you last used.
    @AppStorage("selectedScreen") private var screen: Screen = .today

    private var selection: Binding<Screen?> {
        Binding(get: { screen }, set: { if let s = $0 { screen = s } })
    }

    public init(today: TodayModel, dictionary: DictionaryModel, @ViewBuilder diagnostics: () -> Diagnostics) {
        self.today = today
        self.dictionary = dictionary
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
    return RootView(today: today, dictionary: DictionaryModel(store: store)) { Text("Diagnostics") }
        .frame(width: 1100, height: 800)
}
