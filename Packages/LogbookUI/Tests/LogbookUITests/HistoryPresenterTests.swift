import Foundation
import LogbookCore
import LogbookPersistence
import Testing
@testable import LogbookUI

@Suite struct HistoryPresenterTests {
    nonisolated static let tz = TimeZone(identifier: "Asia/Kolkata")!
    let cal = Calendar.gregorian(in: HistoryPresenterTests.tz)
    let presenter = HistoryPresenter(timeZone: HistoryPresenterTests.tz)
    let calendar = CalendarPresenter(timeZone: HistoryPresenterTests.tz)

    func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    func day(_ d: Int) -> LogicalDay { LogicalDay(year: 2026, month: 11, day: d)! }

    func store() throws -> LogStore {
        let now = at(30, 12)
        return LogStore(database: try AppDatabase.openInMemory(), now: { now }, timeZone: { Self.tz })
    }

    /// Ten days: sleep 00:00–08:00 (day 3 is not logged), work by label,
    /// caffeine rising with day number and sleep shrinking with it.
    func seeded() throws -> LogStore {
        let s = try store()
        for d in 1...10 where d != 3 {
            try s.addBlock(kind: .sleep, start: at(d, 0, d * 5), end: at(d, 8))
            try s.addBlock(kind: .work, start: at(d, 9), end: at(d, 12), label: d.isMultiple(of: 2) ? "Study" : "horizon")
            try s.addBlock(kind: .work, start: at(d, 14), end: at(d, 14, 30), label: "")
            try s.logFood(name: "coffee", nutrition: Nutrition(kcal: 40, caffeineMg: Double(d * 20)), consumedAt: at(d, 10))
        }
        return s
    }

    @Test func seriesKeepsGapsAndShowsTypicalRange() throws {
        let r = try seeded().range(day(1), through: day(10), in: Self.tz)
        let s = presenter.series(Metrics.work, r)
        #expect(s.points.count == 10)
        #expect(s.points[2].value == nil, "day 3 is a gap, not zero")
        #expect(s.points[0].value == 210)
        #expect(s.loggedDays == 9)
        #expect(s.typical?.median == 210)
        #expect(s.headline == "Average 3h 30m over 9 logged days · typical 3h 30m–3h 30m")
        #expect(s.points[1].rolling == nil && s.points[3].rolling == 210, "rolling average needs 3 logged days")
    }

    @Test func sleepWindowsAreRelativeToTheWakeDay() throws {
        let r = try seeded().range(day(1), through: day(10), in: Self.tz)
        let s = presenter.sleepWindows(r)
        #expect(s.windows.count == 9)
        #expect(s.windows.first?.onset == 5 && s.windows.first?.wake == 480)
        #expect(s.headline.hasPrefix("Usually asleep 00:30, awake 08:00 · bedtime varies ±"))
    }

    @Test func workByLabelGroupsAndCountsDeepWork() throws {
        let r = try seeded().range(day(1), through: day(10), in: Self.tz)
        let w = presenter.workByLabel(r, top: 2)
        #expect(w.labels == ["study", "horizon", "other"])
        #expect(w.deepWorkBlocks == 9, "the 30-minute blocks don't count")
        #expect(w.bars.first { $0.day == day(1) && $0.label == "other" }?.minutes == 30, "unlabelled falls into other with top 2")
    }

    @Test func comparisonIsWordedCarefully() throws {
        let r = try seeded().range(day(1), through: day(10), in: Self.tz)
        let c = presenter.compare(Metrics.caffeine, Metrics.sleep, r, nextDay: false)
        #expect(c.points.count == 9)
        #expect(c.sentence.hasPrefix("On days with more caffeine, sleep tended to be lower (a strong relationship, r −1.00 over 9 days, low confidence)."))
        #expect(c.sentence.contains("not a cause"))
        let lagged = presenter.compare(Metrics.caffeine, Metrics.sleep, r, nextDay: true)
        #expect(lagged.points.count == 7, "pairs need today's x and tomorrow's y")
        #expect(lagged.sentence.contains("Not enough paired days yet (7 of 8)"))
    }

    // MARK: Calendar

    @Test func weekStartsOnMonday() {
        #expect(CalendarPresenter.weekStart(day(9)) == day(9), "9 Nov 2026 is a Monday")
        #expect(CalendarPresenter.weekStart(day(15)) == day(9))
        #expect(CalendarPresenter.weekStart(day(16)) == day(16))
        #expect(CalendarPresenter.monthBounds(day(9)) == (day(1), day(30)))
        let feb = CalendarPresenter.monthBounds(LogicalDay("2028-02-10")!)
        #expect(feb.last == LogicalDay("2028-02-29")!)
    }

    @Test func weekSplitsOvernightBlocksAcrossColumns() throws {
        let s = try store()
        try s.addBlock(kind: .sleep, start: at(9, 23), end: at(10, 7))
        let r = try s.range(day(9), through: day(15), in: Self.tz)
        let w = calendar.week(r, today: day(10))
        #expect(w.days.map(\.label).prefix(2) == ["Mon 9", "Tue 10"])
        #expect(w.days[1].isToday)
        #expect(w.items.map(\.column) == ["Mon 9", "Tue 10"])
        #expect(w.items[0].startMinute == 1380 && w.items[1].endMinute == 420)
        #expect(w.title == "9 Nov – 15 Nov 2026")
        #expect(w.days[1].summary == "sleep 8h")
    }

    @Test func monthPadsToMonday() throws {
        let s = try seeded()
        let (first, last) = CalendarPresenter.monthBounds(day(9))
        let m = calendar.month(try s.range(first, through: last, in: Self.tz), today: day(9))
        #expect(m.title == "November 2026")
        #expect(m.cells.prefix(6).allSatisfy { $0 == nil }, "1 Nov 2026 is a Sunday")
        #expect(m.cells[6]?.number == 1)
        #expect(m.cells.compactMap { $0 }.count == 30)
        #expect(m.cells[6]?.lines == ["work 3h 30m", "sleep 7h 55m", "40 kcal"])
        #expect(m.cells.compactMap { $0 }.first { $0.number == 3 }?.hasData == false)
    }
}
