import LogbookCore
import SwiftUI

/// One insight: the finding, how sure it is, and why it's shown.
struct InsightCard: View {
    let insight: Insight
    let model: TodayModel
    @State private var showingWhy = false

    var symbol: String {
        switch insight.kind {
        case .anomaly: "waveform.path.ecg"
        case .trend: "chart.line.uptrend.xyaxis"
        case .correlation: "point.3.connected.trianglepath.dotted"
        case .streak: "star"
        case .habit: "clock"
        case .planning: "calendar.badge.clock"
        case .dataQuality: "square.and.pencil"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(insight.title).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue("\(insight.confidence.rawValue) confidence")
            HStack(spacing: 10) {
                Text("\(insight.confidence.rawValue) confidence").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Why?") { showingWhy.toggle() }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showingWhy, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Why am I seeing this?").font(.headline)
                            ForEach(insight.explanation, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
                            Text("Insights describe patterns in your own log. They aren't advice or a diagnosis.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(width: 340)
                    }
                Menu {
                    Button("Snooze for a week") { model.snoozeInsight(insight) }
                    Button("This looks wrong") { model.insightFeedback(insight, "wrong") }
                    Button("Useful") { model.insightFeedback(insight, "useful") }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button("Dismiss") { model.dismissInsight(insight) }.buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}

#Preview("Insight") {
    InsightCard(insight: Insight(
        detectorID: "caffeine-sleep", detectorVersion: 1, subjectKey: "sleep", kind: .correlation,
        title: "On days with caffeine after 19:15, you slept 48m less the next night",
        explanation: ["Median sleep after 11 days with late caffeine vs 19 days without.", "A pattern in your log, not proof."],
        effect: 1.2, confidence: .moderate, pValue: 0.02, domain: "sleep"
    ), model: PreviewSupport.todayModel())
    .padding()
    .frame(width: 520)
}
