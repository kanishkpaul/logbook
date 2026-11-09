import Charts
import SwiftUI

/// The 24-hour track: one lane each for sleep, work and nature's call, food as
/// marks, and a "now" line. Running blocks are drawn up to now with a stripe.
struct DayTrackChart: View {
    let state: TodayState
    /// Gym, break and other custom kinds get their own lane only when present.
    private var lanes: [String] {
        let hasOther = (state.track + state.plan.ghosts).contains { $0.domain == .other }
        return [Domain.sleep.title, Domain.work.title, Domain.natureCall.title] + (hasOther ? [Domain.other.title] : []) + [Domain.food.title]
    }

    var body: some View {
        Chart {
            // The plan, ghosted behind what happened.
            ForEach(state.plan.ghosts) { item in
                RectangleMark(
                    xStart: .value("Start", item.start),
                    xEnd: .value("End", item.end),
                    y: .value("Lane", item.lane),
                    height: .ratio(0.95)
                )
                .foregroundStyle(item.domain.color.opacity(0.18))
                .cornerRadius(4)
            }
            ForEach(state.track) { item in
                RectangleMark(
                    xStart: .value("Start", item.start),
                    xEnd: .value("End", item.end),
                    y: .value("Lane", item.lane),
                    height: .ratio(0.6)
                )
                .foregroundStyle(item.domain.color.opacity(item.isRunning ? 0.55 : 0.85))
                .cornerRadius(4)
            }
            ForEach(state.foodMarks) { mark in
                PointMark(x: .value("Time", mark.at), y: .value("Lane", Domain.food.title))
                    .symbol(.circle)
                    .symbolSize(40)
                    .foregroundStyle(Domain.food.color)
            }
            if state.window.contains(state.now) {
                RuleMark(x: .value("Now", state.now))
                    .foregroundStyle(.red.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: state.window.start...state.window.end)
        .chartYScale(domain: lanes)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: Date.FormatStyle(locale: Locale(identifier: "en_GB")).hour(.twoDigits(amPM: .omitted)))
            }
        }
        .chartLegend(.hidden)
        .frame(height: 150)
        .accessibilityLabel("24-hour track of sleep, work, nature's call and food, with the plan drawn faintly behind")
        .accessibilityChartDescriptor(DayTrackChartDescriptor(state: state))
    }
}

/// Estimated caffeine and nicotine in the system across the day.
struct SubstanceChart: View {
    let state: TodayState

    var body: some View {
        Chart(state.substances) { p in
            AreaMark(x: .value("Time", p.at), y: .value("mg", p.mg), series: .value("Substance", p.substance.title))
                .foregroundStyle(by: .value("Substance", p.substance.title))
                .opacity(0.35)
            LineMark(x: .value("Time", p.at), y: .value("mg", p.mg), series: .value("Substance", p.substance.title))
                .foregroundStyle(by: .value("Substance", p.substance.title))
        }
        .chartForegroundStyleScale([Domain.caffeine.title: Domain.caffeine.color, Domain.nicotine.title: Domain.nicotine.color])
        .chartXScale(domain: state.window.start...state.window.end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: Date.FormatStyle(locale: Locale(identifier: "en_GB")).hour(.twoDigits(amPM: .omitted)))
            }
        }
        .chartYAxisLabel("mg in system (estimate)")
        .frame(height: 110)
    }
}

#Preview("Day track") {
    let model = PreviewSupport.todayModel()
    return VStack {
        if let state = model.state {
            DayTrackChart(state: state)
            SubstanceChart(state: state)
        } else {
            ProgressView()
        }
    }
    .padding()
    .frame(width: 640)
}
