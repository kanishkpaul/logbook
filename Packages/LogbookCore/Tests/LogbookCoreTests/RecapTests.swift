import Foundation
import Testing
@testable import LogbookCore

@Suite struct RecapTests {
    let facts = [
        RecapFact(id: "work", label: "work today", value: "6h 10m", comparison: "40m above your 4-week average"),
        RecapFact(id: "sleep", label: "last night's sleep", value: "7h 30m", comparison: "about your 4-week average"),
        RecapFact(id: "tasks", label: "tasks done", value: "3 of 5"),
    ]

    @Test func directionsAreWordsNotNumbers() {
        #expect(facts[0].direction == "higher than usual")
        #expect(facts[1].direction == "about usual")
        #expect(facts[2].direction == nil)
        let prompt = RecapPrompt.prompt(facts)
        #expect(!prompt.contains("6h") && !prompt.contains("40m"), "the model never sees values")
        #expect(prompt.contains("id: work; label: work today; direction: higher than usual"))
    }

    @Test func validDraftIsFilledWithVerifiedValues() throws {
        let draft = RecapDraft(headline: "A steady, focused day.", points: [
            .init(factID: "work", phrasing: "You worked {value}, {comparison}."),
            .init(factID: "tasks", phrasing: "Tasks done: {value}."),
        ])
        let r = try RecapValidator.validate(draft, facts: facts)
        #expect(r.sentences == ["You worked 6h 10m, 40m above your 4-week average.", "Tasks done: 3 of 5."])
        #expect(r.source == .onDevice)
    }

    @Test(arguments: [
        (RecapDraft(headline: "You worked 6 hours.", points: [.init(factID: "work", phrasing: "{value}")]), RecapValidator.Problem.digits("You worked 6 hours.")),
        (RecapDraft(headline: "Day.", points: [.init(factID: "steps", phrasing: "{value}")]), .unknownFact("steps")),
        (RecapDraft(headline: "Day.", points: [.init(factID: "work", phrasing: "You worked a lot.")]), .missingValue("You worked a lot.")),
        (RecapDraft(headline: "Day.", points: [.init(factID: "work", phrasing: "{value} {value}")]), .missingValue("{value} {value}")),
        (RecapDraft(headline: "Day.", points: [.init(factID: "tasks", phrasing: "{value}, {comparison}")]), .comparisonWithoutData("{value}, {comparison}")),
        (RecapDraft(headline: "You should rest.", points: [.init(factID: "work", phrasing: "{value}")]), .bannedWord("should")),
        (RecapDraft(headline: "Great job today.", points: [.init(factID: "work", phrasing: "{value}")]), .bannedWord("great job")),
        (RecapDraft(headline: "Day.", points: []), .empty),
        (RecapDraft(headline: "Day.", points: [.init(factID: "work", phrasing: "{value}"), .init(factID: "work", phrasing: "{value}")]), .unknownFact("work")),
    ])
    func rejects(draft: RecapDraft, problem: RecapValidator.Problem) {
        #expect(throws: problem) { try RecapValidator.validate(draft, facts: facts) }
    }

    @Test func templateWorksWithoutAI() {
        let r = RecapTemplate.render(.daily, facts)
        #expect(r.source == .template)
        #expect(r.sentences.first == "Work today: 6h 10m, 40m above your 4-week average.")
    }

    @Test func cacheKeyChangesWithValues() {
        var other = facts
        other[0].value = "6h 20m"
        #expect(RecapPrompt.cacheKey(.daily, facts) != RecapPrompt.cacheKey(.daily, other))
        #expect(RecapPrompt.cacheKey(.daily, facts) == RecapPrompt.cacheKey(.daily, facts))
    }
}

@Suite struct RecapOpeningRulesTests {
    let facts = [
        RecapFact(id: "work", label: "work today", value: "6h 10m", comparison: "40m above your 4-week average"),
        RecapFact(id: "tasks", label: "tasks done", value: "3 of 5"),
    ]

    @Test func appAddsTheComparisonAfterANeutralOpening() throws {
        let r = try RecapValidator.validate(RecapDraft(headline: "Work and a few tasks", points: [
            .init(factID: "work", phrasing: "You put in {value}."),
            .init(factID: "tasks", phrasing: "You finished {value}."),
        ]), facts: facts)
        #expect(r.sentences == ["You put in 6h 10m, 40m above your 4-week average.", "You finished 3 of 5."])
    }

    @Test(arguments: ["You put in more effort {value}.", "You finished more than usual {value}.", "You worked a lot {value}."])
    func openingsThatJudgeAmountsAreRejected(phrasing: String) {
        #expect(throws: RecapValidator.Problem.self) {
            try RecapValidator.validate(RecapDraft(headline: "Work", points: [.init(factID: "work", phrasing: phrasing)]), facts: facts)
        }
    }

    @Test func openingsMustNotBeSentencesOfTheirOwn() {
        #expect(throws: RecapValidator.Problem.self) {
            try RecapValidator.validate(RecapDraft(headline: "Work", points: [.init(factID: "work", phrasing: "You worked hard today. {value}.")]), facts: facts)
        }
        #expect(throws: RecapValidator.Problem.bannedWord("felt")) {
            try RecapValidator.validate(RecapDraft(headline: "Today felt different", points: [.init(factID: "work", phrasing: "You put in {value}.")]), facts: facts)
        }
    }
}
