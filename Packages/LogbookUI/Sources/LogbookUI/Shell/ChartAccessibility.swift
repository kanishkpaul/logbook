import Accessibility
import LogbookCore
import SwiftUI

/// VoiceOver chart descriptions (Audio Graphs) for the main charts. Values
/// come from the presenters; nothing is computed here.

struct SeriesChartDescriptor: AXChartDescriptorRepresentable {
    let series: SeriesState

    func makeChartDescriptor() -> AXChartDescriptor {
        let logged = series.points.compactMap { p in p.value.map { (p.day.description, $0) } }
        let maxValue = logged.map(\.1).max() ?? 1
        let x = AXCategoricalDataAxisDescriptor(title: "Day", categoryOrder: logged.map(\.0))
        let y = AXNumericDataAxisDescriptor(title: series.spec.title, range: 0...max(maxValue, 1), gridlinePositions: []) {
            series.spec.format($0)
        }
        let data = AXDataSeriesDescriptor(name: series.spec.title, isContinuous: false,
                                          dataPoints: logged.map { AXDataPoint(x: $0.0, y: $0.1) })
        return AXChartDescriptor(title: series.spec.title, summary: series.headline, xAxis: x, yAxis: y,
                                 additionalAxes: [], series: [data])
    }
}

struct DayTrackChartDescriptor: AXChartDescriptorRepresentable {
    let state: TodayState

    func makeChartDescriptor() -> AXChartDescriptor {
        let minutes = { (d: Date) in d.timeIntervalSince(state.window.start) / 60 }
        let lanes = Array(Set(state.track.map(\.lane))).sorted()
        let x = AXCategoricalDataAxisDescriptor(title: "Lane", categoryOrder: lanes)
        let y = AXNumericDataAxisDescriptor(title: "Start time", range: 0...1440, gridlinePositions: [360, 720, 1080]) {
            HistoryPresenter.clock($0)
        }
        let series = lanes.map { lane in
            AXDataSeriesDescriptor(name: lane, isContinuous: false, dataPoints: state.track.filter { $0.lane == lane }.map { item in
                AXDataPoint(x: lane, y: minutes(item.start), additionalValues: [],
                            label: "\(item.label.isEmpty ? lane : item.label), \(HistoryPresenter.clock(minutes(item.start))) to \(HistoryPresenter.clock(minutes(item.end)))\(item.isRunning ? ", running" : "")")
            })
        }
        return AXChartDescriptor(title: "Day track", summary: "\(state.track.count) logged blocks today, \(state.plan.items.count) planned",
                                 xAxis: x, yAxis: y, additionalAxes: [], series: series)
    }
}
