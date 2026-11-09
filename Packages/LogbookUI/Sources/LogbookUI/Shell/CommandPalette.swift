import LogbookCore
import SwiftUI

/// One thing you can do from the palette.
public struct PaletteCommand: Identifiable {
    public var id: String
    public var title: String
    public var symbol: String
    public var shortcut: String?
    public var run: () -> Void

    public init(id: String, title: String, symbol: String, shortcut: String? = nil, run: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.run = run
    }

    /// Every word of the query appears in the title (in any order), case-insensitive.
    public static func matches(_ title: String, _ query: String) -> Bool {
        let t = title.lowercased()
        return query.lowercased().split(separator: " ").allSatisfy { t.contains($0) }
    }
}

/// ⌘K: type a few letters, arrows to choose, Return to run, Escape to close.
public struct CommandPalette: View {
    let commands: [PaletteCommand]
    let close: () -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    public init(commands: [PaletteCommand], close: @escaping () -> Void) {
        self.commands = commands
        self.close = close
    }

    private var visible: [PaletteCommand] {
        query.isEmpty ? commands : commands.filter { PaletteCommand.matches($0.title, query) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Go to a screen or run an action", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(runSelected)
                    .onChange(of: query) { selected = 0 }
                    .onKeyPress(.downArrow) { selected = min(selected + 1, max(0, visible.count - 1)); return .handled }
                    .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                List(Array(visible.enumerated()), id: \.element.id) { i, c in
                    HStack {
                        Image(systemName: c.symbol).frame(width: 22).foregroundStyle(.secondary)
                        Text(c.title)
                        Spacer()
                        if let s = c.shortcut { Text(s).foregroundStyle(.secondary).font(.callout.monospaced()) }
                    }
                    .padding(.vertical, 3)
                    .listRowBackground(i == selected ? Color.accentColor.opacity(0.25) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selected = i; runSelected() }
                    .id(i)
                }
                .listStyle(.plain)
                .onChange(of: selected) { proxy.scrollTo(selected) }
            }
            .frame(height: 320)
        }
        .frame(width: 520)
        .onAppear { focused = true }
    }

    private func runSelected() {
        guard visible.indices.contains(selected) else { return }
        let command = visible[selected]
        close()
        command.run()
    }
}

#Preview("Command palette") {
    CommandPalette(commands: RootScreen.allCases.map { s in
        PaletteCommand(id: s.rawValue, title: "Go to \(s.title)", symbol: s.symbol, shortcut: s.shortcutDigit.map { "⌘\($0)" }) {}
    }, close: {})
}
