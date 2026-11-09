import Foundation
import LogbookCore
import LogbookPersistence
import Synchronization

/// A settable clock and sequential UUIDs, so tests are deterministic.
final class TestEnv: Sendable {
    let clock: Mutex<Date>
    let counter = Mutex<UInt64>(0)
    let tz: TimeZone

    init(start: Date, tz: TimeZone = TimeZone(identifier: "Asia/Kolkata")!) {
        clock = Mutex(start)
        self.tz = tz
    }

    var now: Date { clock.withLock { $0 } }
    func set(_ date: Date) { clock.withLock { $0 = date } }
    func advance(minutes: Double) { clock.withLock { $0 = $0.addingTimeInterval(minutes * 60) } }

    func nextUUID() -> UUID {
        let n = counter.withLock { c -> UInt64 in c += 1; return c }
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", n + 0x1000))!
    }

    func store(boundary: DayBoundary = .calendarDay) throws -> LogStore {
        LogStore(
            database: try AppDatabase.openInMemory(),
            boundary: boundary,
            now: { self.now },
            timeZone: { self.tz },
            uuid: { self.nextUUID() }
        )
    }

    /// Wall time in the env's zone.
    func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        Calendar.gregorian(in: tz).date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }
}

func day(_ s: String) -> LogicalDay { LogicalDay(s)! }
