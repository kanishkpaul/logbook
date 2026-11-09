import Foundation
import GRDB
import LogbookCore
import LogbookPersistence
import SQLiteData
import Testing
@testable import LogbookImport

@Suite struct ValuesGrammarTests {
    func values(_ s: String) -> Nutrition? { ShorthandParser.values(s)?.0 }

    @Test func positionalStaysBackwardCompatible() {
        #expect(values("408 / 8 / 0") == Nutrition(kcal: 408, proteinG: 8, caffeineMg: 0))
        #expect(values("cig 4th: 0 / 0 / 0 / 1.2") == nil, "words are not values")
        #expect(values("0 / 0 / 0 / 1.2") == Nutrition(kcal: 0, proteinG: 0, caffeineMg: 0, nicotineMg: 1.2))
    }

    @Test func taggedMacrosGoWhereTheTagSays() {
        #expect(values("180 / 9 / 0 / 0 / 25c / 4f") == Nutrition(kcal: 180, proteinG: 9, carbsG: 25, fatG: 4, caffeineMg: 0, nicotineMg: 0))
        #expect(values("408 60c 12f") == Nutrition(kcal: 408, carbsG: 60, fatG: 12))
        #expect(values("6nic") == Nutrition(nicotineMg: 6))
        #expect(values("408 / 8p / 110") == Nutrition(kcal: 408, proteinG: 8, caffeineMg: 110), "untagged values keep their position")
        #expect(values("210kcal / 0g / 160mg") == Nutrition(kcal: 210, proteinG: 0, caffeineMg: 160))
    }

    @Test func rejectsWhatIsNotValues() {
        #expect(values("homemade") == nil)
        #expect(values("408 / 8 / 9p") == nil, "protein given twice (position 2 and tag)")
        #expect(values("5x") == nil)
        #expect(values("1 / 2 / 3 / 4 / 5") == nil, "only four positional slots")
    }

    @Test func thousandsSeparators() {
        #expect(values("1,616 / 102 / 220") == Nutrition(kcal: 1616, proteinG: 102, caffeineMg: 220))
    }

    @Test func foodLinesUseTheGrammar() throws {
        let f = ShorthandParser.food("dal 200g - 180 / 9 / 0 / 0 / 25c / 4f")
        #expect(f.baseName == "dal" && f.nutrition?.carbsG == 25 && f.nutrition?.fatG == 4)
    }
}

@Suite struct QuickEntryTests {
    static let tz = TimeZone(identifier: "Asia/Kolkata")!
    let now = Calendar.gregorian(in: QuickEntryTests.tz).date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 18))!

    func makeEntry() throws -> QuickEntry {
        let db = try AppDatabase.openInMemory()
        let now = now
        return QuickEntry(store: LogStore(database: db, now: { now }, timeZone: { Self.tz }))
    }

    func log(_ q: QuickEntry, _ text: String) throws -> QuickEntry.Interpretation {
        let i = try q.interpret(text)
        try q.commit(i)
        return i
    }

    @Test func emptyTextPreviewsNothing() throws {
        let i = try makeEntry().interpret("   ")
        #expect(i.lines.isEmpty && !i.canCommit)
    }

    @Test func workBlockPreviewAndCommit() throws {
        let q = try makeEntry()
        let i = try q.interpret("0945-1045 study")
        #expect(i.lines == [.init(kind: "work", title: "Work", detail: "09:45–10:45 · 1h · study")])
        try q.commit(i)
        let s = try q.store.snapshot(of: LogicalDay("2026-11-09")!, in: Self.tz)
        #expect(s.today.workMin == 60)
    }

    @Test func blocksInTheFutureAreRefused() throws {
        let i = try makeEntry().interpret("2300-2330 study")
        #expect(!i.canCommit)
        #expect(i.problem?.contains("future") == true)
    }

    @Test func typedFoodSeedsTheDictionaryThenNamesReuseIt() throws {
        let q = try makeEntry()
        let first = try log(q, "paneer 200g - 530 / 36 / 0 / 0 / 2.4c / 40f")
        #expect(first.lines.map(\.kind) == ["food", "dictionary"])
        #expect(first.lines[0].detail == "530 kcal · P 36 · C 2.4 · F 40")
        #expect(try q.store.dictionary().map(\.name) == ["paneer"])

        let second = try log(q, "paneer 100g")
        #expect(second.lines[0].detail == "265 kcal · P 18 · C 1.2 · F 20")
        #expect(second.lines[1].title == "From the dictionary: paneer")
        let entries = try q.store.snapshot(of: LogicalDay("2026-11-09")!, in: Self.tz).foods
        #expect(entries.map(\.isEstimate) == [false, false], "picking your own dictionary entry is not an estimate")
        #expect(entries.last?.consumedAt == now)
    }

    @Test func nicotineFromTheDictionary() throws {
        let q = try makeEntry()
        var cig = q.store.newFood(name: "cigarette")
        cig.aliasList = ["cig"]
        cig.nutrition = Nutrition(kcal: 0, nicotineMg: 1.2)
        try q.store.saveFood(cig)
        try log(q, "cig x2")
        let facts = try q.store.snapshot(of: LogicalDay("2026-11-09")!, in: Self.tz).today
        #expect(facts.nicotineMg == 2.4)
    }

    @Test func typedValuesAreCompletedFromTheDictionary() throws {
        let q = try makeEntry()
        var pulao = q.store.newFood(name: "pulao")
        pulao.servingSize = 250
        pulao.servingUnit = "g"
        pulao.nutrition = Nutrition(kcal: 400, proteinG: 8, carbsG: 60, fatG: 12, caffeineMg: 0, nicotineMg: 0)
        try q.store.saveFood(pulao)
        let i = try q.interpret("pulao 250g - 408 / 8 / 0")
        #expect(i.lines[0].detail == "408 kcal · P 8 · C 60 · F 12")
    }

    @Test func unknownFoodNeedsValuesButStillLogs() throws {
        let q = try makeEntry()
        let i = try log(q, "Chicken roll")
        #expect(i.lines == [.init(kind: "food", title: "Chicken roll", detail: "needs values")])
        #expect(try q.store.snapshot(of: LogicalDay("2026-11-09")!, in: Self.tz).today.foodNeedingValues == 1)
    }

    @Test func timers() throws {
        let q = try makeEntry()
        #expect(try q.interpret("stop").problem == "No timer to stop")
        try log(q, "start deep work")
        #expect(try q.store.runningBlocks().map(\.label) == ["deep work"])
        #expect(try q.interpret("start study").problem == "A work timer is already running")
        try log(q, "start sleep")
        #expect(try q.interpret("stop").problem?.contains("Several timers") == true)
        try log(q, "stop sleep")
        #expect(try q.store.runningBlocks().map(\.kind) == [.work])
        try log(q, "stop")
        #expect(try q.store.runningBlocks().isEmpty)
    }

    @Test func burnStepsAndTotals() throws {
        let q = try makeEntry()
        let i = try log(q, "burn 373 11773")
        #expect(i.lines.map(\.kind) == ["burn", "steps"])
        let f = try q.store.snapshot(of: LogicalDay("2026-11-09")!, in: Self.tz).today
        #expect(f.burnKcal == 373 && f.steps == 11_773)
        #expect(try q.interpret("$ 6h 30m").problem?.contains("computed") == true)
    }
}

@Suite struct QuickEntryCustomMetricTests {
    static let tz = TimeZone(identifier: "Asia/Kolkata")!

    @Test func logsYourOwnMetricsByName() throws {
        let now = Calendar.gregorian(in: Self.tz).date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8))!
        let q = QuickEntry(store: LogStore(database: try AppDatabase.openInMemory(), now: { now }, timeZone: { Self.tz }))
        try q.store.addMetric(name: "Weight", unit: "kg")
        try q.store.addMetric(name: "Mood", aggregation: .avg)
        let i = try q.interpret("weight 71.2")
        #expect(i.lines == [.init(kind: "metric", title: "Weight", detail: "71.2 kg")])
        try q.commit(i)
        #expect(try q.interpret("mood: 4").lines.first?.title == "Mood")
        #expect(try q.interpret("Weight ~71,5").lines.first?.detail == "71.5 kg (estimate)")
        #expect(try q.interpret("height 180").lines.first?.kind == "food", "not a metric you defined: stays food")
        let sample = try #require(try q.store.snapshot(of: LogicalDay("2026-11-09")!, in: Self.tz).samples.first)
        #expect(sample.key == "weight" && sample.sample.value == 71.2)
    }
}
