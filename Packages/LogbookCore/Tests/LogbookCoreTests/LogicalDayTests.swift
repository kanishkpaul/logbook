import Foundation
import Testing
@testable import LogbookCore

@Suite struct LogicalDayTests {
    @Test func parsesAndFormats() {
        #expect(LogicalDay("2026-10-09")?.description == "2026-10-09")
        #expect(LogicalDay("2026-02-29") == nil)
        #expect(LogicalDay("2024-02-29") != nil)
        #expect(LogicalDay("2026-13-01") == nil)
        #expect(LogicalDay("2026-1-01") == nil)
        #expect(LogicalDay("garbage") == nil)
    }

    @Test func epochRoundTrip() {
        #expect(LogicalDay("1970-01-01")!.daysSinceEpoch == 0)
        #expect(LogicalDay("1969-12-31")!.daysSinceEpoch == -1)
        #expect(LogicalDay("2000-03-01")!.daysSinceEpoch == 11017)
        for z in stride(from: -200_000, through: 200_000, by: 997) {
            #expect(LogicalDay(daysSinceEpoch: z).daysSinceEpoch == z)
        }
    }

    @Test func arithmeticCrossesMonthsYearsAndLeapDays() {
        #expect(TestTime.day("2026-12-31").next == TestTime.day("2027-01-01"))
        #expect(TestTime.day("2024-02-28").next == TestTime.day("2024-02-29"))
        #expect(TestTime.day("2026-02-28").next == TestTime.day("2026-03-01"))
        #expect(TestTime.day("2026-03-01").previous == TestTime.day("2026-02-28"))
        #expect(TestTime.day("2026-08-24").days(to: TestTime.day("2026-10-11")) == 48)
    }

    @Test func orderingIsChronologicalAndMatchesText() {
        let a = TestTime.day("2026-09-30"), b = TestTime.day("2026-10-01")
        #expect(a < b)
        #expect(a.description < b.description)
    }

    @Test func rangeIsInclusiveAndEmptyWhenReversed() {
        let r = LogicalDay.range(TestTime.day("2026-10-30"), through: TestTime.day("2026-11-02"))
        #expect(r.map(\.description) == ["2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02"])
        #expect(LogicalDay.range(TestTime.day("2026-11-02"), through: TestTime.day("2026-11-01")).isEmpty)
    }
}
