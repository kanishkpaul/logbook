import Foundation
import LogbookCore
import Synchronization
import Testing
@testable import LogbookUI

/// A scripted model: returns drafts in order (or throws), counting calls.
final class FakeModel: RecapModel, Sendable {
    let available: Bool
    let script: Mutex<[Result<RecapDraft, any Error>]>
    init(available: Bool = true, _ script: [Result<RecapDraft, any Error>]) {
        self.available = available
        self.script = Mutex(script)
    }
    var isAvailable: Bool { available }
    func draft(instructions: String, prompt: String) async throws -> RecapDraft {
        let next = script.withLock { s -> Result<RecapDraft, any Error> in s.isEmpty ? .failure(CancellationError()) : s.removeFirst() }
        return try next.get()
    }
}

@Suite struct RecapWriterTests {
    let facts = [RecapFact(id: "work", label: "work today", value: "6h 10m", comparison: "40m above your 4-week average")]
    let good = RecapDraft(headline: "A focused day.", points: [.init(factID: "work", phrasing: "You worked {value}, {comparison}.")])
    let bad = RecapDraft(headline: "You worked 6 hours.", points: [.init(factID: "work", phrasing: "{value}")])

    func writer(_ m: FakeModel, ai: Bool = true) -> RecapWriter {
        let w = RecapWriter(model: m)
        w.useOnDeviceModel = ai
        return w
    }

    @Test func validModelOutputIsUsed() async {
        let w = writer(FakeModel([.success(good)]))
        let r = await w.recap(.daily, facts: facts)
        #expect(r.source == .onDevice && r.sentences == ["You worked 6h 10m, 40m above your 4-week average."])
    }

    @Test func invalidOutputIsRetriedOnceThenTemplate() async {
        let retried = writer(FakeModel([.success(bad), .success(good)]))
        #expect(await retried.recap(.daily, facts: facts).source == .onDevice)
        let w = writer(FakeModel([.success(bad), .success(bad), .success(good)]))
        let r = await w.recap(.daily, facts: facts)
        #expect(r.source == .template && w.modelCalls == 2)
    }

    @Test func unavailableOrOffMeansTemplateWithoutCalls() async {
        let off = writer(FakeModel([.success(good)]), ai: false)
        #expect(await off.recap(.daily, facts: facts).source == .template && off.modelCalls == 0)
        let none = writer(FakeModel(available: false, [.success(good)]))
        #expect(await none.recap(.daily, facts: facts).source == .template && none.modelCalls == 0)
    }

    @Test func sameFactsAreCached() async {
        let w = writer(FakeModel([.success(good)]))
        _ = await w.recap(.daily, facts: facts)
        _ = await w.recap(.daily, facts: facts)
        #expect(w.modelCalls == 1)
    }

    /// Opt-in: runs the real on-device model (`LIVE_AI=1`). Proves the prompt,
    /// schema and validator work together on this Mac.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_AI"] != nil))
    func liveOnDeviceModel() async throws {
        let w = RecapWriter(model: OnDeviceRecapModel())
        w.useOnDeviceModel = true
        let facts = [
            RecapFact(id: "work", label: "work today", value: "6h 10m", comparison: "40m above your 4-week average"),
            RecapFact(id: "sleep", label: "last night's sleep", value: "7h 30m", comparison: "about your 4-week average"),
            RecapFact(id: "tasks", label: "tasks done", value: "3 of 5"),
        ]
        let r = await w.recap(.daily, facts: facts)
        print("LIVE RECAP [\(r.source)] \(r.headline) | \(r.sentences.joined(separator: " | ")) | calls \(w.modelCalls)")
        #expect(!r.headline.isEmpty)
    }
}
