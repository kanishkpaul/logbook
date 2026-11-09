import Charts
import LogbookCore
import SwiftUI

/// Bars for logged days (gaps stay empty), a 7-day rolling average line and
/// your typical range as a band. Headline first, as the HIG suggests.
struct MetricChart: View {
    let series: SeriesState
    var height: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(series.spec.title).font(.headline)
            Text(series.headline).font(.callout).foregroundStyle(.secondary)
            Chart {
                if let t = series.typical, let first = series.points.first?.date, let last = series.points.last?.date {
                    RectangleMark(
                        xStart: .value("From", first.addingTimeInterval(-12 * 3600)),
                        xEnd: .value("To", last.addingTimeInterval(12 * 3600)),
                        yStart: .value("Low", t.low),
                        yEnd: .value("High", t.high)
                    )
                    .foregroundStyle(series.spec.domain.color.opacity(0.08))
                }
                ForEach(series.points) { p in
                    if let v = p.value {
                        BarMark(x: .value("Day", p.date, unit: .day), y: .value(series.spec.title, v))
                            .foregroundStyle(series.spec.domain.color.opacity(0.75))
                            .cornerRadius(2)
                    }
                }
                ForEach(series.points) { p in
                    if let r = p.rolling {
                        LineMark(x: .value("Day", p.date, unit: .day), y: .value("7-day average", r))
                            .foregroundStyle(.primary.opacity(0.6))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: series.spec.isDuration ? .stride(by: series.spec.id == "nc_min" ? 30 : 120) : .automatic) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(series.spec.format(v)) }
                    }
                }
            }
            .frame(height: height)
            .accessibilityLabel("\(series.spec.title): \(series.headline)")
            HStack(spacing: 12) {
                Label("7-day average", systemImage: "line.diagonal").foregroundStyle(.secondary)
                if series.typical != nil {
                    Label("typical range", systemImage: "square.fill").foregroundStyle(series.spec.domain.color.opacity(0.4))
                }
            }
            .font(.caption2)
        }
    }
}

/// Range picker shared by history screens.
struct RangePicker: View {
    @Binding var range: HistoryRange

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
    }
}

#Preview("Metric chart") {
    let store = PreviewSupport.store()
    let last = store.boundary.logicalDay(containing: Date(), in: .current)
    let range = try! store.range(last.adding(days: -27), through: last, in: .current)
    return MetricChart(series: HistoryPresenter(timeZone: .current).series(Metrics.work, range))
        .padding()
        .frame(width: 700)
}
