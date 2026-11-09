import Charts
import LogbookCore
import LogbookPersistence
import Observation
import SwiftUI

/// Day / week / month views of what actually happened (the plan layer comes in M6).
@Observable
public final class CalendarModel {
    public enum Mode: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month"
        public var id: String { rawValue }
    }

    public let store: LogStore
    public let dayModel: TodayModel
    public var mode: Mode = .week { didSet { reload() } }
    public private(set) var anchor: LogicalDay
    public private(set) var week: WeekState?
    public private(set) var month: MonthState?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(store: LogStore) {
        self.store = store
        let today = store.boundary.logicalDay(containing: store.now(), in: store.timeZone())
        anchor = today
        dayModel = TodayModel(store: store)
        dayModel.pinnedDay = today
    }

    var today: LogicalDay { store.boundary.logicalDay(containing: store.now(), in: store.timeZone()) }
    var presenter: CalendarPresenter { CalendarPresenter(timeZone: store.timeZone()) }

    public func start() {
        if task == nil {
            dayModel.start()
            reload()
        }
    }

    public func show(_ day: LogicalDay, mode: Mode? = nil) {
        anchor = day
        if let mode, mode != self.mode { self.mode = mode } else { reload() }
    }

    public func step(_ direction: Int) {
        switch mode {
        case .day: anchor = anchor.adding(days: direction)
        case .week: anchor = anchor.adding(days: 7 * direction)
        case .month:
            let (first, _) = CalendarPresenter.monthBounds(anchor)
            anchor = direction > 0 ? CalendarPresenter.monthBounds(first).last.next : first.previous
        }
        reload()
    }

    public func goToToday() {
        anchor = today
        reload()
    }

    private func reload() {
        dayModel.pinnedDay = anchor
        task?.cancel()
        guard mode != .day else { return }
        let (first, last): (LogicalDay, LogicalDay) = mode == .week
            ? (CalendarPresenter.weekStart(anchor), CalendarPresenter.weekStart(anchor).adding(days: 6))
            : CalendarPresenter.monthBounds(anchor)
        let stream = store.observeRange(first, through: last, in: store.timeZone())
        let mode = mode
        task = Task { [weak self] in
            do {
                for try await r in stream {
                    guard let self else { return }
                    if mode == .week { self.week = self.presenter.week(r, today: self.today) }
                    else { self.month = self.presenter.month(r, today: self.today) }
                }
            } catch {
                // Cancelled or the database closed; the next reload starts a fresh observation.
            }
        }
    }
}

public struct CalendarView: View {
    @Bindable var model: CalendarModel

    public init(model: CalendarModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.mode {
            case .day: dayView
            case .week: weekView
            case .month: monthView
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup {
                Button { model.step(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Today") { model.goToToday() }
                Button { model.step(1) } label: { Label("Next", systemImage: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Picker("View", selection: $model.mode) {
                    ForEach(CalendarModel.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .onAppear { model.start() }
    }

    private var title: String {
        switch model.mode {
        case .day: model.dayModel.state?.title ?? "Day"
        case .week: model.week?.title ?? "Week"
        case .month: model.month?.title ?? "Month"
        }
    }

    // MARK: Day

    private var dayView: some View {
        ScrollView {
            if let state = model.dayModel.state {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Day") { DayTrackChart(state: state).padding(.top, 4) }
                    DayLogList(model: model.dayModel, state: state)
                }
                .padding(20)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            } else {
                ProgressView().padding(40)
            }
        }
    }

    // MARK: Week

    private var weekView: some View {
        ScrollView {
            if let week = model.week {
                WeekGrid(week: week) { model.show($0, mode: .day) }.padding(20)
            } else {
                ProgressView().padding(40)
            }
        }
    }

    // MARK: Month

    private var monthView: some View {
        ScrollView {
            if let month = model.month {
                MonthGrid(month: month) { model.show($0, mode: .day) }.padding(20)
            } else {
                ProgressView().padding(40)
            }
        }
    }
}

/// Seven day columns on a 00:00–24:00 grid; tap a day header to open it.
struct WeekGrid: View {
    let week: WeekState
    var open: (LogicalDay) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(week.days) { d in
                    Button { open(d.day) } label: {
                        VStack(spacing: 2) {
                            Text(d.label).fontWeight(d.isToday ? .bold : .regular)
                                .foregroundStyle(d.isToday ? Color.accentColor : .primary)
                            Text(d.summary.isEmpty ? " " : d.summary)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 44)
            Chart(week.items) { item in
                RectangleMark(
                    x: .value("Day", item.column),
                    // Negative minutes put 00:00 at the top and 24:00 at the bottom.
                    yStart: .value("Start", -item.startMinute),
                    yEnd: .value("End", -item.endMinute),
                    width: .ratio(0.85)
                )
                .foregroundStyle(item.domain.color.opacity(0.8))
                .cornerRadius(4)
            }
            .chartXScale(domain: week.days.map(\.label))
            .chartXAxis(.hidden)
            .chartYScale(domain: -1440...0)
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(stride(from: -1440.0, through: 0, by: 120))) { v in
                    AxisGridLine()
                    AxisValueLabel { if let m = v.as(Double.self) { Text(m == -1440 ? "24:00" : HistoryPresenter.clock(-m)) } }
                }
            }
            .frame(height: 760)
        }
    }
}

/// A month of days with their headline numbers; tap a day to open it.
struct MonthGrid: View {
    let month: MonthState
    var open: (LogicalDay) -> Void = { _ in }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) {
                Text($0).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(month.cells.enumerated()), id: \.offset) { _, cell in
                if let cell {
                    Button { open(cell.day) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(cell.number)").fontWeight(cell.isToday ? .bold : .medium)
                                .foregroundStyle(cell.isToday ? Color.accentColor : .primary)
                            ForEach(cell.lines, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                        .background(cell.hasData ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(minHeight: 84)
                }
            }
        }
    }
}

#Preview("Calendar") {
    let m = CalendarModel(store: PreviewSupport.store())
    m.start()
    return NavigationStack { CalendarView(model: m) }.frame(width: 1000, height: 900)
}
