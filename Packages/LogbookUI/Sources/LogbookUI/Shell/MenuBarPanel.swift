import SwiftUI

/// The menu bar popover: running timers, start buttons and Quick Entry.
public struct MenuBarPanel: View {
    let model: TodayModel
    let openMain: () -> Void
    let quit: () -> Void

    public init(model: TodayModel, openMain: @escaping () -> Void, quit: @escaping () -> Void) {
        self.model = model
        self.openMain = openMain
        self.quit = quit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimersBar(model: model)
            Divider()
            QuickEntryField(model: model)
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Button("Open Logbook", action: openMain)
                Spacer()
                Button("Quit", action: quit)
            }
        }
        .padding(14)
        .frame(width: 460)
    }
}

#Preview("Menu bar panel") {
    MenuBarPanel(model: PreviewSupport.todayModel(), openMain: {}, quit: {})
}
