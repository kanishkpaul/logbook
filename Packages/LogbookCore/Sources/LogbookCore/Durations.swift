import Foundation

/// Duration maths and formatting. Durations always come from instants
/// (`end − start`), never from subtracting wall-clock times, so DST days with
/// 23 or 25 hours are handled for free.
public enum Durations {
    /// Whole minutes between two instants, rounded to the nearest minute.
    public static func minutes(from start: Date, to end: Date) -> Int {
        minutes(end.timeIntervalSince(start))
    }

    /// Whole minutes in `seconds`, rounded to the nearest minute.
    public static func minutes(_ seconds: TimeInterval) -> Int {
        Int((seconds / 60).rounded())
    }

    /// The compact style used in the Notes log: `45m`, `1h`, `6h 30m`, `0m`.
    /// Negative values get a leading minus sign.
    public static func compact(minutes total: Int) -> String {
        let sign = total < 0 ? "−" : ""
        let m = abs(total)
        let h = m / 60, r = m % 60
        switch (h, r) {
        case (0, _): return "\(sign)\(r)m"
        case (_, 0): return "\(sign)\(h)h"
        default: return "\(sign)\(h)h \(r)m"
        }
    }

    public static func compact(_ seconds: TimeInterval) -> String {
        compact(minutes: minutes(seconds))
    }

    /// A running-timer clock: `0:04`, `12:05`, `1:12:40` (minutes:seconds under
    /// an hour, hours:minutes:seconds after). Negative input clamps to zero.
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, r)
            : String(format: "%d:%02d", m, r)
    }

    /// Parses the compact style back (`1h`, `45m`, `1h 18m`, `2h30m`).
    public static func parseCompact(_ text: String) -> Int? {
        let s = text.lowercased().replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }
        var total = 0
        var number = ""
        var sawUnit = false
        for ch in s {
            if ch.isNumber {
                number.append(ch)
            } else if ch == "h" || ch == "m" {
                guard let n = Int(number) else { return nil }
                total += ch == "h" ? n * 60 : n
                number = ""
                sawUnit = true
            } else {
                return nil
            }
        }
        return number.isEmpty && sawUnit ? total : nil
    }
}
