import Foundation
import LogbookCore
import LogbookPersistence

/// One metric over a range: bars per logged day, a 7-day rolling average and
/// your typical range (middle half of logged days). Gaps stay gaps.
public struct SeriesState: Equatable {
    public var spec: MetricSpec
    public var points: [Point]
    public var typical: Stats.TypicalRange?
    /// "Average 5h 10m over 24 logged days · typical 4h 30m–6h".
    public var headline: String
    public var loggedDays: Int

    public struct Point: Equatable, Identifiable {
        public var day: LogicalDay
        /// Noon of the day, for date-based x axes.
        public var date: Date
        public var value: Double?
        public var rolling: Double?
        public var id: LogicalDay { day }
    }
}

/// Sleep windows: when you fell asleep and woke, per wake day.
public struct SleepWindowsState: Equatable {
    public var windows: [Window]
    /// "Usually asleep 00:45, awake 08:30 · bedtime varies ±40m".
    public var headline: String

    public struct Window: Equatable, Identifiable {
        public var id: UUID
        public var day: LogicalDay
        public var date: Date
        /// Minutes from the wake day's midnight; negative = the evening before.
        public var onset: Double
        public var wake: Double
    }
}

/// Work per day split by label (top labels, the rest as "other").
public struct WorkByLabelState: Equatable {
    public var bars: [Bar]
    public var labels: [String]
    public var deepWorkBlocks: Int
    public var headline: String

    public struct Bar: Equatable, Identifiable {
        public var day: LogicalDay
        public var date: Date
        public var label: String
        public var minutes: Double
        public var id: String { "\(day)-\(label)" }
    }
}

/// Metric vs metric over paired logged days, with careful wording.
public struct ComparisonState: Equatable {
    public var points: [Point]
    public var line: (intercept: Double, slope: Double)?
    /// "On days with more caffeine, sleep the next day tended to be shorter
    /// (a weak relationship, r −0.24 over 21 days, low confidence)."
    public var sentence: String

    public struct Point: Equatable, Identifiable {
        public var day: LogicalDay
        public var x: Double
        public var y: Double
        public var id: LogicalDay { day }
    }

    public static func == (a: ComparisonState, b: ComparisonState) -> Bool {
        a.points == b.points && a.sentence == b.sentence && a.line?.intercept == b.line?.intercept && a.line?.slope == b.line?.slope
    }
}

public struct HistoryPresenter {
    public var timeZone: TimeZone

    public init(timeZone: TimeZone) {
        self.timeZone = timeZone
    }

    func noon(_ day: LogicalDay) -> Date {
        DayBoundary.calendarDay.start(of: day, in: timeZone).addingTimeInterval(12 * 3600)
    }

    /// Per-day values of a metric over the range (built-in or your own).
    func values(_ spec: MetricSpec, _ r: RangeSnapshot) -> [Double?] {
        if let key = spec.customKey { return r.days.map { r.custom[key]?[$0] } }
        return r.facts.map { spec.value($0) }
    }

    public func series(_ spec: MetricSpec, _ r: RangeSnapshot) -> SeriesState {
        let values = values(spec, r)
        let rolling = Stats.rollingMean(values)
        let points = r.facts.enumerated().map { i, f in
            SeriesState.Point(day: f.logicalDay, date: noon(f.logicalDay), value: values[i], rolling: rolling[i])
        }
        let logged = values.compactMap { $0 }
        let typical = Stats.typicalRange(values)
        var parts: [String] = []
        if !logged.isEmpty {
            parts.append("Average \(spec.format(logged.reduce(0, +) / Double(logged.count))) over \(logged.count) logged day\(logged.count == 1 ? "" : "s")")
        } else {
            parts.append("Nothing logged in this range")
        }
        if let typical { parts.append("typical \(spec.format(typical.low))–\(spec.format(typical.high))") }
        return SeriesState(spec: spec, points: points, typical: typical, headline: parts.joined(separator: " · "), loggedDays: logged.count)
    }

    public func sleepWindows(_ r: RangeSnapshot) -> SleepWindowsState {
        let windows: [SleepWindowsState.Window] = r.blocks
            .filter { $0.kind == .sleep && $0.endUTC != nil && r.days.contains($0.logicalDay) }
            .map { b in
                let midnight = DayBoundary.calendarDay.start(of: b.logicalDay, in: timeZone)
                return .init(id: b.id, day: b.logicalDay, date: noon(b.logicalDay),
                             onset: b.startUTC.timeIntervalSince(midnight) / 60,
                             wake: b.endUTC!.timeIntervalSince(midnight) / 60)
            }
        // The main sleep per day is the longest; naps don't define bedtime.
        let main = Dictionary(grouping: windows, by: \.day).values.compactMap { $0.max { ($0.wake - $0.onset) < ($1.wake - $1.onset) } }
        guard main.count >= 3 else {
            return SleepWindowsState(windows: windows, headline: main.isEmpty ? "No sleep logged in this range" : "Log a few more nights to see your usual times")
        }
        let onsets = main.map(\.onset).sorted(), wakes = main.map(\.wake).sorted()
        let spread = Stats.standardDeviation(onsets.map { Optional($0) }) ?? 0
        let headline = "Usually asleep \(Self.clock(Stats.quantile(onsets, 0.5))), awake \(Self.clock(Stats.quantile(wakes, 0.5))) · bedtime varies ±\(Durations.compact(minutes: Int(spread.rounded())))"
        return SleepWindowsState(windows: windows, headline: headline)
    }

    public func workByLabel(_ r: RangeSnapshot, top: Int = 5) -> WorkByLabelState {
        let work = r.blocks.filter { $0.kind == .work && r.days.contains($0.logicalDay) }
        func minutes(_ b: TimeBlock) -> Double { Double(Durations.minutes(from: b.startUTC, to: b.endUTC ?? b.startUTC)) }
        func name(_ b: TimeBlock) -> String {
            let t = b.label.trimmingCharacters(in: .whitespaces).lowercased()
            return t.isEmpty ? "unlabelled" : t
        }
        let totals = Dictionary(grouping: work, by: name).mapValues { $0.reduce(0) { $0 + minutes($1) } }
        let ranked = totals.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        let kept = Array(ranked.prefix(top))
        var grouped: [String: Double] = [:]
        for b in work {
            let label = kept.contains(name(b)) ? name(b) : "other"
            grouped["\(b.logicalDay)|\(label)", default: 0] += minutes(b)
        }
        let bars = grouped.map { key, value -> WorkByLabelState.Bar in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let day = LogicalDay(parts[0])!
            return .init(day: day, date: noon(day), label: parts[1], minutes: value)
        }.sorted { ($0.day, $0.label) < ($1.day, $1.label) }
        let labels = kept + (ranked.count > top ? ["other"] : [])
        let deep = work.filter { minutes($0) >= 50 }.count
        let headline = work.isEmpty ? "No work logged in this range"
            : "\(deep) deep-work block\(deep == 1 ? "" : "s") (50 min or more) · most time: \(kept.first ?? "—")"
        return WorkByLabelState(bars: bars, labels: labels, deepWorkBlocks: deep, headline: headline)
    }

    /// `x` against `y`, optionally `y` on the next day (e.g. caffeine → next sleep).
    public func compare(_ x: MetricSpec, _ y: MetricSpec, _ r: RangeSnapshot, nextDay: Bool) -> ComparisonState {
        let xs = values(x, r)
        var ys = values(y, r)
        if nextDay { ys = Array(ys.dropFirst()) + [nil] }
        let points = zip(r.facts, zip(xs, ys)).compactMap { f, pair -> ComparisonState.Point? in
            guard let a = pair.0, let b = pair.1 else { return nil }
            return .init(day: f.logicalDay, x: a, y: b)
        }
        let yName = nextDay ? "\(y.title.lowercased()) the next day" : y.title.lowercased()
        guard let c = Stats.correlation(xs, ys) else {
            return ComparisonState(points: points, line: nil,
                                   sentence: "Not enough paired days yet (\(points.count) of 8) to say anything about \(x.title.lowercased()) and \(yName).")
        }
        let sentence: String
        if abs(c.r) < 0.1 {
            sentence = "No clear relationship between \(x.title.lowercased()) and \(yName) (r \(Self.r(c.r)) over \(c.n) days)."
        } else {
            sentence = "On days with more \(x.title.lowercased()), \(yName) tended to be \(c.direction) (\(c.strength), r \(Self.r(c.r)) over \(c.n) days, \(c.confidence)). This is a pattern in your log, not a cause."
        }
        return ComparisonState(points: points, line: Stats.linearFit(xs, ys), sentence: sentence)
    }

    static func r(_ v: Double) -> String {
        (v < 0 ? "−" : "") + String(format: "%.2f", abs(v))
    }

    /// Minutes from midnight (may be negative or past 24 h) as `HH:mm`.
    static func clock(_ minutes: Double) -> String {
        let m = ((Int(minutes.rounded()) % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
