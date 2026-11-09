import Charts
import LogbookCore
import SwiftUI

/// Work: daily totals vs your typical range, and where the time went by label.
public struct WorkView: View {
    @Bindable var model: HistoryModel

    public init(model: HistoryModel) {
        self.model = model
    }

    public var body: some View {
        HistoryScaffold(title: "Work", model: model) { r, p in
            MetricChart(series: p.series(Metrics.work, r))
            WorkByLabelChart(state: p.workByLabel(r))
        }
    }
}

/// Sleep: duration vs typical range, and the window you slept in each night.
public struct SleepView: View {
    @Bindable var model: HistoryModel

    public init(model: HistoryModel) {
        self.model = model
    }

    public var body: some View {
        HistoryScaffold(title: "Sleep", model: model) { r, p in
            MetricChart(series: p.series(Metrics.sleep, r))
            SleepWindowChart(state: p.sleepWindows(r))
        }
    }
}

/// Body: logged burn, steps, net kcal and nature's call, descriptive only.
public struct BodyView: View {
    @Bindable var model: HistoryModel

    public init(model: HistoryModel) {
        self.model = model
    }

    public var body: some View {
        HistoryScaffold(title: "Body", model: model) { r, p in
            MetricChart(series: p.series(Metrics.burn, r), height: 150)
            MetricChart(series: p.series(Metrics.steps, r), height: 150)
            MetricChart(series: p.series(Metrics.net, r), height: 150)
            Text("Net kcal is intake minus logged burn, not total energy balance.").font(.caption).foregroundStyle(.secondary)
            MetricChart(series: p.series(Metrics.ncCount, r), height: 120)
            MetricChart(series: p.series(Metrics.ncMinutes, r), height: 120)
            Text("Nature's call charts are descriptive only. For anything health-related, a clinician is the right person to ask.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Trends: any metric over a range, and metric-vs-metric with honest wording.
public struct TrendsView: View {
    @Bindable var model: HistoryModel
    @AppStorage("trends.metric") private var metric = "work"
    @AppStorage("trends.x") private var xMetric = "caffeine"
    @AppStorage("trends.y") private var yMetric = "sleep"
    @AppStorage("trends.nextDay") private var nextDay = true

    public init(model: HistoryModel) {
        self.model = model
    }

    public var body: some View {
        HistoryScaffold(title: "Trends", model: model) { r, p in
            Picker("Metric", selection: $metric) {
                ForEach(Metrics.all) { Text($0.title).tag($0.id) }
            }
            .frame(width: 260)
            MetricChart(series: p.series(Metrics.spec(metric), r))

            Divider()
            Text("Compare").font(.headline)
            HStack {
                Picker("On days with more", selection: $xMetric) {
                    ForEach(Metrics.all) { Text($0.title).tag($0.id) }
                }
                Picker("how was", selection: $yMetric) {
                    ForEach(Metrics.all) { Text($0.title).tag($0.id) }
                }
                Toggle("the next day", isOn: $nextDay)
            }
            .frame(maxWidth: 700)
            ComparisonChart(x: Metrics.spec(xMetric), y: Metrics.spec(yMetric), nextDay: nextDay,
                            state: p.compare(Metrics.spec(xMetric), Metrics.spec(yMetric), r, nextDay: nextDay))
        }
    }
}

struct WorkByLabelChart: View {
    let state: WorkByLabelState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("By label").font(.headline)
            Text(state.headline).font(.callout).foregroundStyle(.secondary)
            Chart(state.bars) { bar in
                BarMark(x: .value("Day", bar.date, unit: .day), y: .value("Minutes", bar.minutes))
                    .foregroundStyle(by: .value("Label", bar.label))
            }
            .chartForegroundStyleScale(domain: state.labels)
            .chartYAxis {
                AxisMarks(values: .stride(by: 120)) { v in
                    AxisGridLine()
                    AxisValueLabel { if let m = v.as(Double.self) { Text(Durations.compact(minutes: Int(m))) } }
                }
            }
            .frame(height: 200)
        }
    }
}

struct SleepWindowChart: View {
    let state: SleepWindowsState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sleep window").font(.headline)
            Text(state.headline).font(.callout).foregroundStyle(.secondary)
            Chart(state.windows) { w in
                // Negative values put earlier times at the top.
                BarMark(x: .value("Day", w.date, unit: .day), yStart: .value("Asleep", -w.onset), yEnd: .value("Awake", -w.wake))
                    .foregroundStyle(Domain.sleep.color.opacity(0.75))
                    .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(values: .stride(by: 120)) { v in
                    AxisGridLine()
                    AxisValueLabel { if let m = v.as(Double.self) { Text(HistoryPresenter.clock(-m)) } }
                }
            }
            .frame(height: 220)
        }
    }
}

struct ComparisonChart: View {
    let x: MetricSpec
    let y: MetricSpec
    let nextDay: Bool
    let state: ComparisonState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.sentence).font(.callout)
            Chart {
                ForEach(state.points) { pt in
                    PointMark(x: .value(x.title, pt.x), y: .value(y.title, pt.y))
                        .foregroundStyle(y.domain.color)
                }
                if let line = state.line, let lo = state.points.map(\.x).min(), let hi = state.points.map(\.x).max(), lo < hi {
                    LineMark(x: .value(x.title, lo), y: .value(y.title, line.intercept + line.slope * lo), series: .value("fit", "fit"))
                        .foregroundStyle(.secondary)
                    LineMark(x: .value(x.title, hi), y: .value(y.title, line.intercept + line.slope * hi), series: .value("fit", "fit"))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: x.isDuration ? .stride(by: 120) : .automatic) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text(x.format(d)) } }
                }
            }
            .chartYAxis {
                AxisMarks(values: y.isDuration ? .stride(by: 120) : .automatic) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text(y.format(d)) } }
                }
            }
            .chartXAxisLabel(x.title)
            .chartYAxisLabel(nextDay ? "\(y.title), next day" : y.title)
            .frame(height: 260)
        }
    }
}

/// Shared frame: range picker, scroll view, empty/loading states.
struct HistoryScaffold<Content: View>: View {
    let title: String
    @Bindable var model: HistoryModel
    @ViewBuilder let content: (RangeSnapshot, HistoryPresenter) -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let r = model.snapshot {
                    content(r, model.presenter)
                } else {
                    ProgressView()
                }
                if let error = model.lastError { Text(error).foregroundStyle(.red) }
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem { RangePicker(range: $model.range) }
        }
        .onAppear { model.start() }
    }
}

import LogbookPersistence

#Preview("Work") {
    let m = HistoryModel(store: PreviewSupport.store())
    m.start()
    return NavigationStack { WorkView(model: m) }.frame(width: 900, height: 700)
}

#Preview("Sleep") {
    let m = HistoryModel(store: PreviewSupport.store())
    m.start()
    return NavigationStack { SleepView(model: m) }.frame(width: 900, height: 700)
}

#Preview("Body") {
    let m = HistoryModel(store: PreviewSupport.store())
    m.start()
    return NavigationStack { BodyView(model: m) }.frame(width: 900, height: 900)
}

#Preview("Trends") {
    let m = HistoryModel(store: PreviewSupport.store())
    m.start()
    return NavigationStack { TrendsView(model: m) }.frame(width: 900, height: 900)
}
