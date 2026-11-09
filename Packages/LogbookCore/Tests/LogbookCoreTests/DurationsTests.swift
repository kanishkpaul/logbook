import Foundation
import Testing
@testable import LogbookCore

@Suite struct DurationsTests {
    @Test(arguments: [
        (0, "0m"), (13, "13m"), (60, "1h"), (78, "1h 18m"), (390, "6h 30m"), (525, "8h 45m"), (-40, "−40m"),
    ])
    func compact(minutes: Int, text: String) {
        #expect(Durations.compact(minutes: minutes) == text)
    }

    @Test(arguments: [
        ("1h", 60), ("45m", 45), ("1h 18m", 78), ("2h30m", 150), ("8h 45m", 525), ("13m", 13),
    ])
    func parsesCompact(text: String, minutes: Int) {
        #expect(Durations.parseCompact(text) == minutes)
    }

    @Test(arguments: ["", "h", "12", "1x", "1h 3"])
    func rejectsMalformed(text: String) {
        #expect(Durations.parseCompact(text) == nil)
    }

    @Test(arguments: [(0.0, "0:00"), (4.9, "0:04"), (725, "12:05"), (4360, "1:12:40"), (-5, "0:00"), (36000, "10:00:00")])
    func clock(seconds: Double, text: String) {
        #expect(Durations.clock(seconds) == text)
    }

    @Test func roundsToNearestMinute() {
        #expect(Durations.minutes(89) == 1)
        #expect(Durations.minutes(91) == 2)
    }
}

@Suite struct NutritionTests {
    @Test func scalesKnownFieldsAndKeepsUnknown() {
        let n = Nutrition(kcal: 163.2, proteinG: 3.2, caffeineMg: nil).scaled(by: 2.5)
        #expect(n.kcal == 408)
        #expect(n.proteinG == 8)
        #expect(n.caffeineMg == nil)
        #expect(!n.isEmpty)
        #expect(Nutrition().isEmpty)
    }
}
