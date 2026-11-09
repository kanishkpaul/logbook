import Foundation
import Testing
@testable import LogbookCore

@Suite struct StatsTests {
    @Test func rollingMeanSkipsGapsAndNeedsEnoughDays() {
        let v: [Double?] = [1, nil, 3, nil, nil, 5, 7, nil, 9]
        let r = Stats.rollingMean(v, window: 3, minimum: 2)
        #expect(r[0] == nil && r[1] == nil)
        #expect(r[2] == 2, "mean of 1 and 3; the gap is skipped")
        #expect(r[3] == nil, "only 3 is in the window")
        #expect(r[6] == 6)
        #expect(r[8] == 8)
    }

    @Test func typicalRangeIsTheMiddleHalf() throws {
        let range = try #require(Stats.typicalRange([1, 2, 3, 4, 5, 6, 7, 8, 9, nil]))
        #expect(range.low == 3 && range.median == 5 && range.high == 7 && range.days == 9)
        #expect(Stats.typicalRange([1, 2, 3]) == nil)
    }

    @Test func standardDeviation() {
        #expect(Stats.standardDeviation([2, 4, 4, 4, 5, 5, 7, 9]) == 2)
        #expect(Stats.standardDeviation([3, nil]) == nil)
    }

    @Test func correlationUsesPairedLoggedDaysOnly() throws {
        let x: [Double?] = [1, 2, 3, 4, 5, 6, 7, 8, nil, 10]
        let y: [Double?] = [2, 4, 6, 8, 10, 12, 14, 16, 18, nil]
        let c = try #require(Stats.correlation(x, y))
        #expect(c.n == 8)
        #expect(abs(c.r - 1) < 1e-12)
        #expect(c.strength == "a strong relationship")
        #expect(c.confidence == "low confidence")
        #expect(Stats.correlation([1, 2, 3], [1, 2, 3]) == nil, "too few days")
        #expect(Stats.correlation(Array(repeating: 1, count: 10), Array(1...10).map(Double.init)) == nil, "no variation")
    }

    @Test func linearFit() throws {
        let fit = try #require(Stats.linearFit([1, 2, 3, nil], [3, 5, 7, 100]))
        #expect(fit.intercept == 1 && fit.slope == 2)
    }

    @Test func dayPartsSplitOvernightBlocks() {
        let tz = TimeZone(identifier: "Asia/Kolkata")!
        let cal = Calendar.gregorian(in: tz)
        let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 30))!
        let end = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 7))!
        let parts = DayPart.parts(start: start, end: end, in: tz)
        #expect(parts.map(\.day.description) == ["2026-11-08", "2026-11-09"])
        #expect(parts[0].startMinute == 1410 && parts[0].endMinute == 1440)
        #expect(parts[1].startMinute == 0 && parts[1].endMinute == 420)
    }

    @Test func dayPartsFitA25HourDayInto24() {
        let paris = TimeZone(identifier: "Europe/Paris")!
        let w = DayBoundary.calendarDay.interval(of: LogicalDay("2026-10-25")!, in: paris)
        let parts = DayPart.parts(start: w.start, end: w.end, in: paris)
        #expect(parts.count == 1 && parts[0].startMinute == 0 && parts[0].endMinute == 1440)
    }
}
