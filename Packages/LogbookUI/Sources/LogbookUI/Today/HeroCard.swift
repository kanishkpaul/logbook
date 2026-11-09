import Charts
import LogbookCore
import SwiftUI

/// One pinned metric: big rounded number, a neutral headline and a 14-day
/// sparkline in which days without data are gaps, not zeros.
struct HeroCard: View {
    let hero: TodayState.Hero

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(hero.title, systemImage: hero.domain.symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(hero.domain.color)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(hero.value)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if !hero.unit.isEmpty {
                    Text(hero.unit).font(.callout).foregroundStyle(.secondary)
                }
            }
            Text(hero.headline ?? hero.detail ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .help([hero.headline, hero.detail].compactMap { $0 }.joined(separator: "\n"))
            Chart(hero.spark) { point in
                if let v = point.value {
                    BarMark(x: .value("Day", point.day.description), y: .value(hero.title, v))
                        .foregroundStyle(hero.domain.color.opacity(point.id == hero.spark.last?.id ? 0.9 : 0.35))
                        .cornerRadius(1.5)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 28)
            .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hero.title)
        .accessibilityValue([hero.value + (hero.unit.isEmpty ? "" : " \(hero.unit)"), hero.headline, hero.detail].compactMap { $0 }.joined(separator: ", "))
    }
}

#Preview("Hero") {
    HeroCard(hero: .init(
        id: "work", domain: .work, title: "Work today", value: "6h 10m", unit: "",
        headline: "40m above your 4-week average", detail: nil,
        spark: (0..<14).map { .init(day: LogicalDay("2026-11-01")!.adding(days: $0), value: $0 % 5 == 0 ? nil : Double(200 + $0 * 10)) }
    ))
    .frame(width: 220)
    .padding()
}
