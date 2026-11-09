import Foundation
import LogbookCore
import LogbookPersistence
import Testing
@testable import LogbookUI

@Suite struct ReviewPresenterTests {
    nonisolated static let tz = TimeZone(identifier: "Asia/Kolkata")!
    let cal = Calendar.gregorian(in: ReviewPresenterTests.tz)

    func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    @Test func comparesTheWeekWithTheOneBefore() throws {
        let now = at(15, 21)
        let s = LogStore(database: try AppDatabase.openInMemory(), now: { now }, timeZone: { Self.tz })
        // Week before (2–8 Nov): 4h a day on 5 days. This week (9–15 Nov): 5h a day on 6 days, Thu 7h.
        for d in 2...6 { try s.addBlock(kind: .work, start: at(d, 9), end: at(d, 13)) }
        for d in 9...14 { try s.addBlock(kind: .work, start: at(d, 9), end: at(d, d == 12 ? 16 : 14)) }
        for d in 9...15 { try s.addBlock(kind: .sleep, start: at(d, 0, 30), end: at(d, 8)) }
        for d in 9...15 { try s.logFood(name: "x", nutrition: Nutrition(kcal: 2000, proteinG: 100, carbsG: 250, fatG: 60, caffeineMg: 150), consumedAt: at(d, 13)) }
        try s.logFood(name: "cig", nutrition: Nutrition(kcal: 0, nicotineMg: 1.2), consumedAt: at(10, 16))
        let t = try s.addTask(NewTask(title: "deck"))
        try s.completeTask(id: t.id)
        let week = LogicalDay("2026-11-09")!
        let range = try s.range(week.adding(days: -7), through: week.adding(days: 6), in: Self.tz)
        let r = ReviewPresenter(timeZone: Self.tz).present(range, tasks: try s.taskRows(includeDoneSince: at(2, 0)), weekStart: week)
        #expect(r.title == "Week of 9 Nov – 15 Nov")
        #expect(r.loggedDays == 7)
        let lines = Dictionary(uniqueKeysWithValues: r.sections.map { ($0.title, $0.lines) })
        #expect(lines["Work"]?[0] == "You worked 32h (5h 20m a day on 6 logged days), 1h 20m a day more than the week before.")
        #expect(lines["Work"]?[1] == "Longest day: Thursday, 7h.")
        #expect(lines["Sleep"]?[0] == "You slept 7h 30m a night on average (7 nights).")
        #expect(lines["Sleep"]?[1].hasPrefix("Usually asleep around 00:30") == true)
        #expect(lines["Food"]?[0] == "A typical day: 2000 kcal · P 100 · C 250 · F 60 (7 logged days).")
        #expect(lines["Food"]?.contains("Nicotine: 1.2 mg this week, 1.2 mg more than the week before.") == true)
        #expect(lines["Plan"] == ["1 task done."])
        for line in r.sections.flatMap(\.lines) { #expect(InsightText.violations(line).isEmpty, "\(line)") }
    }
}
