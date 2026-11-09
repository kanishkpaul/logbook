import Foundation
import LogbookCore
import Testing
@testable import LogbookPersistence

@Suite struct RangeSnapshotTests {
    let env = TestEnv(start: Date(timeIntervalSince1970: 0))

    @Test func rangeHasEveryDayAndOverlappingFinishedBlocks() throws {
        env.set(env.at(2026, 11, 9, 20, 0))
        let store = try env.store()
        try store.addBlock(kind: .sleep, start: env.at(2026, 11, 1, 23, 0), end: env.at(2026, 11, 2, 7, 0))
        try store.addBlock(kind: .work, start: env.at(2026, 11, 3, 9, 0), end: env.at(2026, 11, 3, 12, 0))
        try store.addBlock(kind: .work, start: env.at(2026, 11, 8, 9, 0), end: env.at(2026, 11, 8, 10, 0))
        try store.startBlock(kind: .work)
        let r = try store.range(LogicalDay("2026-11-02")!, through: LogicalDay("2026-11-04")!, in: env.tz)
        #expect(r.days.map(\.description) == ["2026-11-02", "2026-11-03", "2026-11-04"])
        #expect(r.facts.map(\.isEmpty) == [false, false, true])
        #expect(r.blocks.map(\.kind) == [.sleep, .work], "the overnight sleep overlaps; running and out-of-range blocks don't")
    }

    @Test func observationEmitsOnChange() async throws {
        env.set(env.at(2026, 11, 9, 20, 0))
        let store = try env.store()
        var it = store.observeRange(LogicalDay("2026-11-09")!, through: LogicalDay("2026-11-09")!, in: env.tz).makeAsyncIterator()
        #expect(try await it.next()?.blocks.isEmpty == true)
        try store.addBlock(kind: .work, start: env.at(2026, 11, 9, 9, 0), end: env.at(2026, 11, 9, 10, 0))
        #expect(try await it.next()?.blocks.count == 1)
    }
}
