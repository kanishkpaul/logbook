import SwiftUI

/// Today: Quick Entry, pinned metrics, timers, the 24-hour track, substances
/// in the system, and the day's log.
public struct TodayView: View {
    let model: TodayModel
    @Binding var closingDay: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var go: (RootScreen) -> Void

    public init(model: TodayModel, closingDay: Binding<Bool> = .constant(false), go: @escaping (RootScreen) -> Void = { _ in }) {
        self.model = model
        _closingDay = closingDay
        self.go = go
    }

    public var body: some View {
        ScrollView {
            if let state = model.state {
                VStack(alignment: .leading, spacing: 20) {
                    QuickEntryField(model: model)
                    QuickAddBar(model: model)

                    if model.showWelcome {
                        WelcomeCard(model: model, go: go)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                        ForEach(state.heroes) { HeroCard(hero: $0) }
                    }

                    if !model.insights.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Noticed").font(.headline)
                            ForEach(model.insights) { InsightCard(insight: $0, model: model) }
                        }
                    }

                    GroupBox("Plan") {
                        PlanPanel(model: model, plan: state.plan).padding(4)
                    }

                    GroupBox("Timers") {
                        TimersBar(model: model).padding(4)
                    }

                    GroupBox("Day") {
                        DayTrackChart(state: state).padding(.top, 4)
                    }

                    if !state.substances.isEmpty, state.substances.contains(where: { $0.mg > 0.05 }) {
                        GroupBox("In your system") {
                            SubstanceChart(state: state).padding(.top, 4)
                        }
                    }

                    DayLogList(model: model, state: state)

                    if let error = model.lastError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
                .padding(20)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
                // Numbers count to new values and cards settle in; off with Reduce Motion.
                .animation(reduceMotion ? nil : .spring(duration: 0.35), value: state.heroes)
                .animation(reduceMotion ? nil : .spring(duration: 0.35), value: model.insights)
            } else {
                ProgressView().padding(40)
            }
        }
        .navigationTitle(model.state?.title ?? "Today")
        .toolbar {
            ToolbarItem {
                Button {
                    closingDay = true
                } label: {
                    Label("Close the day", systemImage: "moon.zzz")
                }
                .help("Fill gaps, burn and missing values, then plan tomorrow (⇧⌘D)")
            }
        }
        .sheet(isPresented: $closingDay) { CloseDayView(model: model) }
    }
}

#Preview("Today") {
    NavigationStack {
        TodayView(model: PreviewSupport.todayModel())
    }
    .frame(width: 900, height: 900)
}
