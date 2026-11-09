import Foundation
import Testing
@testable import LogbookCore

/// The date-maths matrix from the research report: midnight crossings, day
/// starts of 0 and 4, DST in Paris (23/25-hour days) and Havana (transition at
/// midnight), and time-zone changes mid-block.
@Suite struct DayBoundaryTests {
    let k = TestTime.kolkata
    let at = TestTime.at
    let day = TestTime.day
    let h = 3600.0

    // MARK: Attribution matrix (work → start day, sleep → wake day)

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let kind: BlockKind
        let start: (Int, Int, Int, Int, Int)
        let end: (Int, Int, Int, Int, Int)
        let dayStartHour: Int
        let expected: String
        var testDescription: String { "\(name) @\(dayStartHour)h" }
    }

    static let matrix: [Case] = [
        // 22:50–00:00: starts on the 9th either way.
        Case(name: "work 2250-0000", kind: .work, start: (2026, 10, 9, 22, 50), end: (2026, 10, 10, 0, 0), dayStartHour: 0, expected: "2026-10-09"),
        Case(name: "work 2250-0000", kind: .work, start: (2026, 10, 9, 22, 50), end: (2026, 10, 10, 0, 0), dayStartHour: 4, expected: "2026-10-09"),
        // 01:00–03:30: the tail of the 9th only under a 4 AM day start.
        Case(name: "work 0100-0330", kind: .work, start: (2026, 10, 10, 1, 0), end: (2026, 10, 10, 3, 30), dayStartHour: 0, expected: "2026-10-10"),
        Case(name: "work 0100-0330", kind: .work, start: (2026, 10, 10, 1, 0), end: (2026, 10, 10, 3, 30), dayStartHour: 4, expected: "2026-10-09"),
        // Sleep counts toward the day you wake up.
        Case(name: "sleep 2300-0700", kind: .sleep, start: (2026, 10, 9, 23, 0), end: (2026, 10, 10, 7, 0), dayStartHour: 0, expected: "2026-10-10"),
        Case(name: "sleep 2300-0700", kind: .sleep, start: (2026, 10, 9, 23, 0), end: (2026, 10, 10, 7, 0), dayStartHour: 4, expected: "2026-10-10"),
        Case(name: "sleep 0515-1055", kind: .sleep, start: (2026, 10, 10, 5, 15), end: (2026, 10, 10, 10, 55), dayStartHour: 4, expected: "2026-10-10"),
        // Waking before the day start (03:00 under 4 AM) is still the previous logical day.
        Case(name: "sleep nap 0100-0300", kind: .sleep, start: (2026, 10, 10, 1, 0), end: (2026, 10, 10, 3, 0), dayStartHour: 4, expected: "2026-10-09"),
        Case(name: "nc 1550-1708", kind: .natureCall, start: (2026, 10, 10, 15, 50), end: (2026, 10, 10, 17, 8), dayStartHour: 4, expected: "2026-10-10"),
        // Exactly at the boundary belongs to the new day.
        Case(name: "work at 0400", kind: .work, start: (2026, 10, 10, 4, 0), end: (2026, 10, 10, 5, 0), dayStartHour: 4, expected: "2026-10-10"),
        Case(name: "work at 0359", kind: .work, start: (2026, 10, 10, 3, 59), end: (2026, 10, 10, 5, 0), dayStartHour: 4, expected: "2026-10-09"),
    ]

    @Test(arguments: matrix)
    func attribution(_ c: Case) {
        let s = at(c.start.0, c.start.1, c.start.2, c.start.3, c.start.4, k)
        let e = at(c.end.0, c.end.1, c.end.2, c.end.3, c.end.4, k)
        let d = Attribution.day(kind: c.kind, start: s, end: e, boundary: DayBoundary(hour: c.dayStartHour), timeZone: k)
        #expect(d.description == c.expected)
    }

    @Test func runningSleepIsProvisionallyAttributedByStart() {
        let s = at(2026, 10, 9, 23, 0, k)
        let d = Attribution.day(kind: .sleep, start: s, end: nil, boundary: .calendarDay, timeZone: k)
        #expect(d == day("2026-10-09"))
    }

    // MARK: Day intervals and DST

    @Test func ordinaryDayIs24Hours() {
        let i = DayBoundary(hour: 4).interval(of: day("2026-10-09"), in: k)
        #expect(i.start == at(2026, 10, 9, 4, 0, k))
        #expect(i.duration == 24 * h)
    }

    @Test func parisSpringForwardDayIs23Hours() {
        // 29 Mar 2026: 02:00 → 03:00.
        #expect(DayBoundary.calendarDay.interval(of: day("2026-03-29"), in: TestTime.paris).duration == 23 * h)
        // With a 4 AM start, the short day is the 28th (04:00 on 28th → 04:00 on 29th).
        #expect(DayBoundary(hour: 4).interval(of: day("2026-03-28"), in: TestTime.paris).duration == 23 * h)
        #expect(DayBoundary(hour: 4).interval(of: day("2026-03-29"), in: TestTime.paris).duration == 24 * h)
    }

    @Test func parisFallBackDayIs25Hours() {
        // 25 Oct 2026: 03:00 → 02:00.
        #expect(DayBoundary.calendarDay.interval(of: day("2026-10-25"), in: TestTime.paris).duration == 25 * h)
        #expect(DayBoundary(hour: 4).interval(of: day("2026-10-24"), in: TestTime.paris).duration == 25 * h)
    }

    @Test func dayStartInsideSpringForwardGapStartsAfterTheGap() {
        // 02:30 does not exist on 29 Mar in Paris; the day starts at 03:00.
        let b = DayBoundary(hour: 2, minute: 30)
        #expect(b.start(of: day("2026-03-29"), in: TestTime.paris) == at(2026, 3, 29, 3, 0, TestTime.paris))
    }

    @Test func dayStartInsideRepeatedHourUsesFirstOccurrence() {
        // 02:30 happens twice on 25 Oct in Paris (00:30 and 01:30 UTC).
        let b = DayBoundary(hour: 2, minute: 30)
        let start = b.start(of: day("2026-10-25"), in: TestTime.paris)
        #expect(start == TestTime.utc(2026, 10, 25, 0, 30))
        #expect(b.interval(of: day("2026-10-25"), in: TestTime.paris).duration == 25 * h)
        // The second 02:15 (01:15 UTC) is after the day started, so it is the 25th.
        #expect(b.logicalDay(containing: TestTime.utc(2026, 10, 25, 1, 15), in: TestTime.paris) == day("2026-10-25"))
    }

    @Test func havanaMidnightTransition() {
        // 8 Mar 2026: 00:00 → 01:00, so midnight does not exist.
        let spring = DayBoundary.calendarDay.interval(of: day("2026-03-08"), in: TestTime.havana)
        #expect(spring.start == at(2026, 3, 8, 1, 0, TestTime.havana))
        #expect(spring.duration == 23 * h)
        // The tz database keeps Cuba on DST through 2026; the next fall-back is
        // 7 Nov 2027, 01:00 → 00:00, so that day has 25 hours.
        #expect(DayBoundary.calendarDay.interval(of: day("2027-11-07"), in: TestTime.havana).duration == 25 * h)
        // An instant in the repeated hour is still 7 Nov.
        let repeated = DayBoundary.calendarDay.interval(of: day("2027-11-07"), in: TestTime.havana).start.addingTimeInterval(1.5 * h)
        #expect(DayBoundary.calendarDay.logicalDay(containing: repeated, in: TestTime.havana) == day("2027-11-07"))
    }

    @Test func durationAcrossDSTComesFromInstants() {
        // 01:30 → 03:30 on spring-forward night is one real hour.
        let s = at(2026, 3, 29, 1, 30, TestTime.paris), e = at(2026, 3, 29, 3, 30, TestTime.paris)
        #expect(Durations.minutes(from: s, to: e) == 60)
        // 22:00 → 06:00 across fall-back is nine real hours.
        let s2 = at(2026, 10, 24, 22, 0, TestTime.paris), e2 = at(2026, 10, 25, 6, 0, TestTime.paris)
        #expect(Durations.minutes(from: s2, to: e2) == 9 * 60)
    }

    @Test func blockAcrossTimeZones() {
        // Sleep starts 20:00 in Kolkata, ends 08:00 in London next day.
        let s = at(2026, 10, 10, 20, 0, k)       // 14:30 UTC
        let e = at(2026, 10, 11, 8, 0, TestTime.london) // 07:00 UTC (BST)
        #expect(Durations.minutes(from: s, to: e) == 16 * 60 + 30)
        let d = Attribution.day(kind: .sleep, start: s, end: e, boundary: .calendarDay, timeZone: TestTime.london)
        #expect(d == day("2026-10-11"))
    }

    // MARK: Clipping

    @Test func clipsOvernightSleepAtTheBoundary() {
        let s = at(2026, 10, 9, 23, 0, k), e = at(2026, 10, 10, 7, 0, k)
        let cal = DayBoundary.calendarDay.clip(start: s, end: e, in: k)
        #expect(cal.map(\.day) == [day("2026-10-09"), day("2026-10-10")])
        #expect(cal.map(\.interval.duration) == [1 * h, 7 * h])

        let four = DayBoundary(hour: 4).clip(start: s, end: e, in: k)
        #expect(four.map(\.day) == [day("2026-10-09"), day("2026-10-10")])
        #expect(four.map(\.interval.duration) == [5 * h, 3 * h])
    }

    @Test func clipInsideOneDayIsOneSegment() {
        let s = at(2026, 10, 10, 9, 45, k), e = at(2026, 10, 10, 10, 45, k)
        let segs = DayBoundary.calendarDay.clip(start: s, end: e, in: k)
        #expect(segs.count == 1)
        #expect(segs[0].interval.duration == h)
    }

    @Test func clipEmptyOrReversedIsEmpty() {
        let s = at(2026, 10, 10, 9, 45, k)
        #expect(DayBoundary.calendarDay.clip(start: s, end: s, in: k).isEmpty)
        #expect(DayBoundary.calendarDay.clip(start: s, end: s.addingTimeInterval(-60), in: k).isEmpty)
    }

    @Test(arguments: [TestTime.kolkata, TestTime.paris, TestTime.havana, TestTime.london, TestTime.utcZone])
    func clippedSegmentsAlwaysSumToTheTotal(tz: TimeZone) {
        var rng = SeededRNG(seed: 0xC0FFEE ^ UInt64(abs(tz.identifier.hashValue % 1000)))
        let base = TestTime.utc(2026, 1, 1, 0, 0)
        let boundaries = [DayBoundary(hour: 0), DayBoundary(hour: 4), DayBoundary(hour: 2, minute: 30), DayBoundary(hour: 23, minute: 59)]
        for _ in 0..<400 {
            let start = base.addingTimeInterval(Double(Int.random(in: 0..<(365 * 24 * 60), using: &rng)) * 60)
            let end = start.addingTimeInterval(Double(Int.random(in: 1..<(72 * 60), using: &rng)) * 60)
            let b = boundaries.randomElement(using: &rng)!
            let segs = b.clip(start: start, end: end, in: tz)
            #expect(segs.reduce(0) { $0 + $1.interval.duration } == end.timeIntervalSince(start))
            #expect(segs.first?.interval.start == start)
            #expect(segs.last?.interval.end == end)
            for (a, n) in zip(segs, segs.dropFirst()) {
                #expect(a.interval.end == n.interval.start)
                #expect(n.day == a.day.next)
            }
            for seg in segs {
                let window = b.interval(of: seg.day, in: tz)
                #expect(seg.interval.start >= window.start && seg.interval.end <= window.end)
            }
        }
    }

    @Test(arguments: [TestTime.kolkata, TestTime.paris, TestTime.havana])
    func everyInstantLiesInsideItsLogicalDay(tz: TimeZone) {
        var rng = SeededRNG(seed: 42)
        let base = TestTime.utc(2026, 1, 1, 0, 0)
        for b in [DayBoundary(hour: 0), DayBoundary(hour: 4), DayBoundary(hour: 2, minute: 30)] {
            for _ in 0..<500 {
                let t = base.addingTimeInterval(Double(Int.random(in: 0..<(366 * 24 * 3600), using: &rng)))
                let d = b.logicalDay(containing: t, in: tz)
                let i = b.interval(of: d, in: tz)
                #expect(t >= i.start && t < i.end, "\(t) not in \(d) for \(tz.identifier) @\(b.startMinutes)")
            }
        }
    }
}
