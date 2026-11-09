import Foundation
import Testing
@testable import LogbookCore

@Suite struct RecurrenceTests {
    func d(_ s: String) -> LogicalDay { LogicalDay(s)! }

    @Test func parsesAndRoundTrips() {
        for rule in ["FREQ=DAILY", "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE", "AFTER;FREQ=DAILY;INTERVAL=3", "FREQ=MONTHLY"] {
            #expect(Recurrence(rule: rule)?.description == rule)
        }
        #expect(Recurrence(rule: "FREQ=YEARLY") == nil)
        #expect(Recurrence(rule: "FREQ=DAILY;BYDAY=MO") == nil, "BYDAY is weekly only")
        #expect(Recurrence(rule: "INTERVAL=2") == nil)
    }

    @Test func isoWeekday() {
        #expect(d("2026-11-09").isoWeekday == 1, "Monday")
        #expect(d("2026-11-15").isoWeekday == 7, "Sunday")
        #expect(d("1970-01-01").isoWeekday == 4)
    }

    @Test func daily() {
        let r = Recurrence(frequency: .daily, interval: 3)
        let anchor = d("2026-11-01")
        #expect(r.next(after: anchor, anchor: anchor) == d("2026-11-04"))
        #expect(r.next(after: d("2026-11-05"), anchor: anchor) == d("2026-11-07"))
        #expect(r.next(after: d("2026-10-01"), anchor: anchor) == anchor)
    }

    @Test func weeklyOnDays() {
        let r = Recurrence(frequency: .weekly, weekdays: [1, 3]) // Mon, Wed
        let anchor = d("2026-11-09") // Mon
        #expect(r.next(after: anchor, anchor: anchor) == d("2026-11-11"))
        #expect(r.next(after: d("2026-11-11"), anchor: anchor) == d("2026-11-16"))
    }

    @Test func everyOtherWeek() {
        let r = Recurrence(frequency: .weekly, interval: 2)
        let anchor = d("2026-11-10") // Tue
        #expect(r.next(after: anchor, anchor: anchor) == d("2026-11-24"))
        #expect(r.next(after: d("2026-11-24"), anchor: anchor) == d("2026-12-08"))
    }

    @Test func monthlyClampsToMonthEnd() {
        let r = Recurrence(frequency: .monthly)
        let anchor = d("2026-01-31")
        #expect(r.next(after: anchor, anchor: anchor) == d("2026-02-28"))
        #expect(r.next(after: d("2026-02-28"), anchor: anchor) == d("2026-03-31"))
        #expect(r.next(after: d("2028-01-31"), anchor: anchor) == d("2028-02-29"))
    }

    @Test func afterCompletionCountsFromTheDoneDay() {
        let r = Recurrence(frequency: .daily, interval: 3, afterCompletion: true)
        #expect(r.next(after: d("2026-11-12"), anchor: d("2026-11-01")) == d("2026-11-15"))
    }

    @Test func crossesDSTWithoutShifting() {
        // Logical days only: the transition night is just another day.
        let r = Recurrence(frequency: .daily)
        #expect(r.next(after: d("2026-03-28"), anchor: d("2026-03-01")) == d("2026-03-29"))
    }

    @Test func summaries() {
        #expect(Recurrence(frequency: .weekly, weekdays: [1, 2, 3, 4, 5]).summary == "every weekday")
        #expect(Recurrence(frequency: .weekly, interval: 2, weekdays: [1, 3]).summary == "every 2 weeks on Mon, Wed")
        #expect(Recurrence(frequency: .daily, interval: 3, afterCompletion: true).summary == "3 days after done")
    }
}
