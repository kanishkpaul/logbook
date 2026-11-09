import Foundation
import LogbookCore
import Testing
@testable import LogbookImport

@Suite struct DateHeaderTests {
    func parse(_ s: String, previous: String? = nil) -> String? {
        DateHeader.parse(s, previous: previous.flatMap { LogicalDay($0) }, defaultYear: 2026)?.description
    }

    @Test(arguments: [
        ("2026-10-10", "2026-10-10"),
        ("10 Oct", "2026-10-10"),
        ("Fri 10 Oct 2026", "2026-10-10"),
        ("Friday, 10 October 2026", "2026-10-10"),
        ("10th October", "2026-10-10"),
        ("Oct 10, 2026", "2026-10-10"),
        ("Sept 3", "2026-09-03"),
        ("10/10/2026", "2026-10-10"),
        ("03.09.26", "2026-09-03"),
        ("24-08-2026", "2026-08-24"),
        ("10 Oct:", "2026-10-10"),
    ])
    func accepts(text: String, expected: String) {
        #expect(parse(text) == expected)
    }

    @Test(arguments: ["pulao 250g", "10 Oct study", "31 Feb", "Oct", "0945 - 1045", "burn - 373", "2026-13-01", "Raw notes"])
    func rejects(text: String) {
        #expect(parse(text) == nil)
    }

    @Test func yearlessHeadersFollowThePreviousYearAndRollOver() {
        #expect(parse("2 Jan", previous: "2026-12-30") == "2027-01-02")
        #expect(parse("12 Oct", previous: "2026-10-11") == "2026-10-12")
        #expect(parse("1 Oct", previous: "2027-01-05") == "2027-10-01", "a backward jump under 6 months stays in the year")
    }
}

@Suite struct ShorthandParserTests {
    let parser = ShorthandParser(defaultYear: 2026)
    let day = LogicalDay("2026-10-10")!

    func entry(_ line: String) -> ParsedEntry? {
        if case .entry(let e) = parser.parseLine(line, on: day) { return e }
        return nil
    }

    func block(_ line: String) -> ParsedBlock? {
        if case .block(let b)? = entry(line) { return b }
        return nil
    }

    func food(_ line: String) -> ParsedFood? {
        if case .food(let f)? = entry(line) { return f }
        return nil
    }

    // MARK: Blocks

    @Test func workLine() throws {
        let b = try #require(block("0945 - 1045 [1h] > study + exam"))
        #expect(b.kind == .work)
        #expect(b.start == WallTime(day: day, minutes: 9 * 60 + 45))
        #expect(b.end == WallTime(day: day, minutes: 10 * 60 + 45))
        #expect(b.typedMinutes == 60)
        #expect(b.label == "study + exam")
    }

    @Test(arguments: ["945-1045 study", "09:45 – 10:45 > study", "work 0945 - 1045 > study", "0945 to 1045 study"])
    func workVariants(line: String) throws {
        let b = try #require(block(line))
        #expect(b.kind == .work)
        #expect(b.start.minutes == 585 && b.end.minutes == 645)
        #expect(b.label == "study")
    }

    @Test func workAcrossMidnightEndsNextDay() throws {
        let b = try #require(block("2250 - 0000 [1h 10m] > pocf"))
        #expect(b.end == WallTime(day: day.next, minutes: 0))
        let c = try #require(block("2300 - 2400 > pocf"))
        #expect(c.end == WallTime(day: day, minutes: 1440))
    }

    @Test func sleepEndsOnTheHeaderDate() throws {
        let a = try #require(block("sleep -> 0045 - 0930 [8h 45m]"))
        #expect(a.kind == .sleep)
        #expect(a.start == WallTime(day: day, minutes: 45))
        #expect(a.end == WallTime(day: day, minutes: 570))
        #expect(a.typedMinutes == 525)
        let b = try #require(block("sleep 2330-0700"))
        #expect(b.start == WallTime(day: day.previous, minutes: 23 * 60 + 30))
        #expect(b.end == WallTime(day: day, minutes: 420))
    }

    @Test func natureCallKeepsOnlyTheTotal() throws {
        let b = try #require(block("nc -> 1550 - 1708 [1h 18m] [13m / 17m / 48m]"))
        #expect(b.kind == .natureCall)
        #expect(b.typedMinutes == 78)
        #expect(b.label == "")
    }

    @Test(arguments: ["sleep -> late", "nc -> 1550", "sleep 2561-0700"])
    func unreadableKeywordTimesAreIssues(line: String) {
        guard case .issue(.unreadableTimes, _) = parser.parseLine(line, on: day) else {
            Issue.record("expected unreadableTimes for \(line)")
            return
        }
    }

    // MARK: Metrics and totals

    @Test func burnAndSteps() {
        #expect(entry("burn - 373 / 11,773 steps") == .burn(kcal: 373, steps: 11_773, isEstimate: false))
        #expect(entry("Burn - 373 kcal") == .burn(kcal: 373, steps: nil, isEstimate: false))
        #expect(entry("burn 373 11773") == .burn(kcal: 373, steps: 11_773, isEstimate: false))
        #expect(entry("burn ~400") == .burn(kcal: 400, steps: nil, isEstimate: true))
        #expect(entry("steps 9,120") == .steps(9120, isEstimate: false))
        #expect(entry("9120 steps") == .steps(9120, isEstimate: false))
    }

    @Test func totals() {
        #expect(entry("$ 6h 30m") == .workTotal(minutes: 390))
        #expect(entry("$ 1616 / 102 / 220") == .nutritionTotal(Nutrition(kcal: 1616, proteinG: 102, caffeineMg: 220)))
        guard case .issue(.unreadableTotal, _) = parser.parseLine("$ lots", on: day) else {
            Issue.record("expected unreadableTotal")
            return
        }
    }

    // MARK: Food

    @Test func foodWithValuesAndQuantity() throws {
        let f = try #require(food("pulao 250g - 408 / 8 / 0"))
        #expect(f.name == "pulao 250g")
        #expect(f.baseName == "pulao")
        #expect(f.quantity == 250 && f.unit == "g")
        #expect(f.nutrition == Nutrition(kcal: 408, proteinG: 8, caffeineMg: 0))
        #expect(!f.isEstimate)
    }

    @Test func foodEstimatesAndUnits() throws {
        let a = try #require(food("~thali - 1290 / 28 / 0"))
        #expect(a.isEstimate && a.baseName == "thali")
        let b = try #require(food("coffee - ~40 / 1 / 110"))
        #expect(b.isEstimate && b.nutrition?.caffeineMg == 110)
        let c = try #require(food("Monster - 210kcal / 0g / 160mg"))
        #expect(c.nutrition == Nutrition(kcal: 210, proteinG: 0, caffeineMg: 160))
        let d = try #require(food("protein shake - 120"))
        #expect(d.nutrition == Nutrition(kcal: 120, proteinG: nil, caffeineMg: nil))
    }

    @Test func foodWithoutValues() throws {
        let a = try #require(food("Chicken roll"))
        #expect(a.nutrition == nil && a.baseName == "Chicken roll")
        let b = try #require(food("50rs puchka"))
        #expect(b.nutrition == nil && b.quantity == nil)
        let c = try #require(food("egg x2"))
        #expect(c.baseName == "egg" && c.quantity == 2 && c.unit == "x")
    }

    @Test func dashesInsideNamesAreNotValueSeparators() throws {
        let a = try #require(food("roti-sabzi"))
        #expect(a.nutrition == nil && a.name == "roti-sabzi")
        let b = try #require(food("coffee 50 ml + 2 tsp - 40 / 1 / 110"))
        #expect(b.name == "coffee 50 ml + 2 tsp")
        #expect(b.baseName == "coffee 50 ml + 2 tsp", "a quantity after '+' is not stripped")
        #expect(b.nutrition?.kcal == 40)
    }

    @Test func numberRangesWithUnitsAreFoodNotWork() throws {
        let f = try #require(food("100 - 200g paneer"))
        #expect(f.nutrition == nil)
        let b = try #require(block("0945-1045>study"))
        #expect(b.label == "study")
    }

    @Test func foodTimePrefix() throws {
        let f = try #require(food("13:30 pulao 250g - 408 / 8 / 0"))
        #expect(f.timeMinutes == 13 * 60 + 30)
        #expect(f.baseName == "pulao")
    }

    // MARK: Documents

    @Test func documentStructureAndIssues() {
        let text = """
            stray line before any day
            # Log
            ## Fri 10 Oct 2026
            ```
            - 0945 - 1045 [1h] > study
            pulao 250g - 408 / 8 / 0
            ```
            | day | kcal |
            |---|---|
            ---

            ## 11 Oct
            sleep -> 0100 - 0800
            ## 10 Oct
            Chicken roll
            """
        let doc = parser.parse(text)
        #expect(doc.days.map(\.date.description) == ["2026-10-10", "2026-10-11"])
        #expect(doc.days[0].lines.count == 3, "the repeated 10 Oct merges into the first")
        #expect(doc.days[1].lines.count == 1)
        #expect(doc.issues.map(\.code) == [.noDayYet, .repeatedDay])
        #expect(doc.days[0].lines[0].line.number == 5)
        #expect(doc.days[0].lines[0].line.text == "- 0945 - 1045 [1h] > study")
    }
}
