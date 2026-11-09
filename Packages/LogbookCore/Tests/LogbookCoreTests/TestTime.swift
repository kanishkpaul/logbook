import Foundation
import LogbookCore

/// Time zones and an instant builder for date-maths tests.
///
/// `TestTime.at` traps on wall times that don't exist or are ambiguous, so a
/// mistake in test setup fails loudly instead of silently shifting by an hour.
/// Use `TestTime.utc` to name an instant inside a repeated (fall-back) hour.
enum TestTime {
    static let utcZone = TimeZone(identifier: "UTC")!
    /// The user's zone: no DST.
    static let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    /// 23- and 25-hour days at 02:00/03:00 local.
    static let paris = TimeZone(identifier: "Europe/Paris")!
    /// DST transition at local midnight (the day starts at 01:00 in March).
    static let havana = TimeZone(identifier: "America/Havana")!
    static let london = TimeZone(identifier: "Europe/London")!

    static func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ tz: TimeZone) -> Date {
        let cal = Calendar.gregorian(in: tz)
        let comps = DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)
        guard let date = cal.date(from: comps) else { fatalError("no date for \(comps)") }
        let back = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        precondition(
            back.year == y && back.month == mo && back.day == d && back.hour == h && back.minute == mi,
            "wall time \(comps) does not exist in \(tz.identifier)"
        )
        // Ambiguous if the same wall time also exists one hour later or earlier.
        for shift in [-3600.0, 3600.0] {
            let other = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date.addingTimeInterval(shift))
            precondition(
                !(other.year == y && other.month == mo && other.day == d && other.hour == h && other.minute == mi),
                "wall time \(comps) is ambiguous in \(tz.identifier); use TestTime.utc"
            )
        }
        return date
    }

    static func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        at(y, mo, d, h, mi, utcZone)
    }

    static func day(_ s: String) -> LogicalDay { LogicalDay(s)! }
}

/// Small deterministic RNG for property tests (SplitMix64).
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
