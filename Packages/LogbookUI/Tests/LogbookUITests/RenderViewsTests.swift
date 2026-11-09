import AppKit
import Foundation
import SwiftUI
import Testing
@testable import LogbookUI

/// Renders views on synthetic preview data to PNGs for a visual check.
/// Opt-in: runs only when `RENDER_DIR` is set, e.g.
/// `RENDER_DIR=/tmp/shots swift test --package-path Packages/LogbookUI --filter RenderViews`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DIR"] != nil))
struct RenderViewsTests {
    let dir = URL(filePath: ProcessInfo.processInfo.environment["RENDER_DIR"] ?? "/tmp")

    func readyModel() async throws -> TodayModel {
        let model = PreviewSupport.todayModel()
        for _ in 0..<50 where model.state == nil { try await Task.sleep(for: .milliseconds(50)) }
        return try #require(model.state == nil ? nil : model)
    }

    func render<V: View>(_ view: V, _ name: String, width: CGFloat) throws {
        let renderer = ImageRenderer(content: view.frame(width: width).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try png.write(to: dir.appending(path: "\(name).png"))
    }

    @Test func renderToday() async throws {
        let model = try await readyModel()
        let state = try #require(model.state)
        try render(VStack(alignment: .leading, spacing: 16) {
            SubstanceChart(state: state)
            DayLogList(model: model, state: state)
        }.padding(), "today-lower", width: 860)
        try render(VStack(alignment: .leading) {
            QuickAddBar(model: model)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                ForEach(state.heroes) { HeroCard(hero: $0) }
            }
        }.padding(), "today-top", width: 860)
        try render(CloseDayView(model: model), "close-day", width: 520)
        try render(MenuBarPanel(model: model, openMain: {}, quit: {}), "menu-bar-panel", width: 460)
        try render(QuickEntryField(model: model, text: "paneer 200g - 530 / 36 / 0 / 0 / 2.4c / 40f").padding(), "quick-entry-new-food", width: 620)
        try render(QuickEntryField(model: model, text: "cig x2").padding(), "quick-entry-dictionary", width: 620)
        try render(QuickEntryField(model: model, text: "start sleep").padding(), "quick-entry-timer", width: 620)
    }

    @Test func renderHistory() async throws {
        let store = PreviewSupport.store()
        let tz = TimeZone.current
        let last = store.boundary.logicalDay(containing: Date(), in: tz)
        let r = try store.range(last.adding(days: -27), through: last, in: tz)
        let p = HistoryPresenter(timeZone: tz)
        try render(VStack(alignment: .leading, spacing: 24) {
            MetricChart(series: p.series(Metrics.work, r))
            WorkByLabelChart(state: p.workByLabel(r))
            MetricChart(series: p.series(Metrics.sleep, r))
            SleepWindowChart(state: p.sleepWindows(r))
            ComparisonChart(x: Metrics.work, y: Metrics.sleep, nextDay: false, state: p.compare(Metrics.work, Metrics.sleep, r, nextDay: false))
        }.padding(), "history", width: 860)
        let c = CalendarPresenter(timeZone: tz)
        let ws = CalendarPresenter.weekStart(last)
        try render(WeekGrid(week: c.week(try store.range(ws, through: ws.adding(days: 6), in: tz), today: last)).padding(), "week", width: 900)
        let (f, l) = CalendarPresenter.monthBounds(last)
        try render(MonthGrid(month: c.month(try store.range(f, through: l, in: tz), today: last)).padding(), "month", width: 900)
    }
}
