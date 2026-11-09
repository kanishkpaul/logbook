import SwiftUI

/// Today: Quick Entry, pinned metrics, timers, the 24-hour track, substances
/// in the system, and the day's log.
public struct TodayView: View {
    let model: TodayModel
    @State private var closingDay = false

    public init(model: TodayModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            if let state = model.state {
                VStack(alignment: .leading, spacing: 20) {
                    QuickEntryField(model: model)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                        ForEach(state.heroes) { HeroCard(hero: $0) }
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
                .help("Fill gaps, burn and missing values, then see the day's summary")
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
