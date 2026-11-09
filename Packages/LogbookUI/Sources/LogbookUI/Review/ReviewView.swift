import LogbookCore
import LogbookPersistence
import Observation
import SwiftUI

@Observable
public final class ReviewModel {
    public let store: LogStore
    public private(set) var weekStart: LogicalDay
    public private(set) var state: ReviewState?
    public var lastError: String?

    public init(store: LogStore) {
        self.store = store
        let today = store.boundary.logicalDay(containing: store.now(), in: store.timeZone())
        weekStart = CalendarPresenter.weekStart(today)
    }

    public func load() {
        do {
            let tz = store.timeZone()
            let range = try store.range(weekStart.adding(days: -7), through: weekStart.adding(days: 6), in: tz)
            let since = DayBoundary.calendarDay.start(of: weekStart.adding(days: -7), in: tz)
            state = ReviewPresenter(timeZone: tz).present(range, tasks: try store.taskRows(includeDoneSince: since), weekStart: weekStart)
        } catch {
            lastError = "\(error)"
        }
    }

    public func step(_ weeks: Int) {
        weekStart = weekStart.adding(days: 7 * weeks)
        load()
    }
}

public struct ReviewView: View {
    let model: ReviewModel
    let insights: [Insight]
    let writer: RecapWriter

    public init(model: ReviewModel, insights: [Insight], writer: RecapWriter = RecapWriter()) {
        self.model = model
        self.insights = insights
        self.writer = writer
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let state = model.state {
                    Text("\(state.loggedDays) of 7 days logged").foregroundStyle(.secondary)
                    if !state.facts.isEmpty {
                        GroupBox("In short") {
                            RecapView(kind: .weekly, facts: state.facts, writer: writer)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                        }
                    }
                    if state.sections.isEmpty {
                        ContentUnavailableView("Nothing logged this week", systemImage: "calendar")
                    }
                    ForEach(state.sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(section.title, systemImage: section.domain.symbol)
                                .font(.headline).foregroundStyle(section.domain.color)
                            ForEach(section.lines, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                    if !insights.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Noticed", systemImage: "sparkle.magnifyingglass").font(.headline)
                            ForEach(insights) { Text("• \($0.title)") }
                        }
                    }
                }
                if let error = model.lastError { Text(error).foregroundStyle(.red) }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.state?.title ?? "Review")
        .toolbar {
            ToolbarItemGroup {
                Button { model.step(-1) } label: { Label("Previous week", systemImage: "chevron.left") }
                Button { model.step(1) } label: { Label("Next week", systemImage: "chevron.right") }
            }
        }
        .onAppear { model.load() }
    }
}

#Preview("Review") {
    NavigationStack { ReviewView(model: ReviewModel(store: PreviewSupport.store()), insights: []) }
        .frame(width: 800, height: 700)
}
