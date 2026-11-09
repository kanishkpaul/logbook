import SwiftUI

/// First run: the four ways in. Disappears once something is logged.
struct WelcomeCard: View {
    let model: TodayModel
    var go: (RootScreen) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Welcome to Logbook").font(.title3.bold())
                Spacer()
                Button("Hide") { model.dismissWelcome() }.buttonStyle(.borderless)
            }
            step(1, "Log in your Notes shorthand",
                 "Type in the field above, or press ⌥Space anywhere: “0945-1045 study”, “pulao 250g - 408 / 8 / 0”, “sleep 0045-0930”, “burn 373 11773”.")
            step(2, "Bring your history", "Paste days from Notes, preview, and import as one undoable batch.") {
                Button("Open Import") { go(.importing) }
            }
            step(3, "Build your dictionary",
                 "Foods you type with values are added automatically. Fill in carbs, fat, caffeine and nicotine once; then just type the name.") {
                Button("Open Dictionary") { go(.dictionary) }
            }
            step(4, "Plan, then compare", "“t write deck ~45m fri” adds a task; “plan 1400-1600 deep work” blocks time. ⌘K finds everything.")
        }
        .padding(16)
        .background(Domain.work.color.opacity(0.08), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Domain.work.color.opacity(0.25)))
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        step(n, title, detail) { EmptyView() }
    }

    private func step<Action: View>(_ n: Int, _ title: String, _ detail: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.callout.bold().monospacedDigit()).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Domain.work.color, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            action()
        }
    }
}

#Preview("Welcome") {
    WelcomeCard(model: PreviewSupport.todayModel()) { _ in }
        .padding()
        .frame(width: 760)
}
