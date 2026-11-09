import Foundation
import LogbookCore

/// Parses the Notes shorthand (see docs/IMPORT_FORMAT.md) into days and entries.
///
/// Pure and line-oriented: no time zone, no database. Every skipped line
/// becomes an issue; nothing is silently dropped.
public struct ShorthandParser: Sendable {
    public var defaultYear: Int

    public init(defaultYear: Int) {
        self.defaultYear = defaultYear
    }

    public func parse(_ text: String) -> ParsedDocument {
        var doc = ParsedDocument()
        var current: ParsedDay?
        var seenDays: Set<LogicalDay> = []
        var lastDate: LogicalDay?

        func flush() {
            guard let day = current else { return }
            if let i = doc.days.firstIndex(where: { $0.date == day.date }) {
                doc.days[i].lines += day.lines
            } else {
                doc.days.append(day)
            }
            current = nil
        }

        let rawLines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        doc.lineCount = rawLines.count
        for (index, raw) in rawLines.enumerated() {
            let number = index + 1
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if Self.isIgnorable(trimmed) { continue }

            let isHeading = trimmed.hasPrefix("#")
            let body = Self.stripMarkers(trimmed)
            if body.isEmpty { continue }
            let source = SourceLine(number: number, text: trimmed)

            if let date = DateHeader.parse(body, previous: lastDate, defaultYear: defaultYear) {
                flush()
                if seenDays.contains(date) {
                    doc.issues.append(.init(severity: .warning, code: .repeatedDay, line: number, day: date,
                                            message: "\(date) appears more than once; its lines are merged"))
                }
                seenDays.insert(date)
                lastDate = date
                current = ParsedDay(date: date, header: source)
                continue
            }
            if isHeading { continue } // a non-date heading, e.g. "## Raw notes"

            guard let day = current?.date else {
                doc.issues.append(.init(severity: .error, code: .noDayYet, line: number, day: nil,
                                        message: "no day header before this line: \(trimmed)"))
                continue
            }
            switch parseLine(body, on: day) {
            case .entry(let entry):
                current?.lines.append(ParsedLine(line: source, entry: entry))
            case .issue(let code, let message):
                doc.issues.append(.init(severity: code == .unreadableTotal ? .warning : .error,
                                        code: code, line: number, day: day, message: message))
            }
        }
        flush()
        return doc
    }

    // MARK: Lines

    enum LineResult {
        case entry(ParsedEntry)
        case issue(ImportIssue.Code, String)
    }

    func parseLine(_ s: String, on day: LogicalDay) -> LineResult {
        let lower = s.lowercased()

        if s.hasPrefix("$") {
            let rest = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let minutes = Durations.parseCompact(rest) { return .entry(.workTotal(minutes: minutes)) }
            if let (n, _) = Self.values(rest) { return .entry(.nutritionTotal(n)) }
            return .issue(.unreadableTotal, "can't read total: \(s)")
        }

        if let rest = Self.afterKeyword(lower, s, keywords: ["sleep"]) {
            guard let r = Self.range(rest) else { return .issue(.unreadableTimes, "can't read sleep times: \(s)") }
            // Sleep ends on the header's date; it started the evening before if start > end.
            var start = WallTime(day: day, minutes: r.start)
            let end = WallTime(day: day, minutes: r.end)
            if r.start > r.end { start.day = day.previous }
            return .entry(.block(ParsedBlock(kind: .sleep, start: start, end: end, label: "",
                                             typedMinutes: r.typedMinutes, isEstimate: r.isEstimate)))
        }

        if let rest = Self.afterKeyword(lower, s, keywords: ["nc"]) {
            guard let r = Self.range(rest) else { return .issue(.unreadableTimes, "can't read nature's-call times: \(s)") }
            return .entry(.block(Self.forwardBlock(.natureCall, r, on: day, label: "")))
        }

        if let rest = Self.afterKeyword(lower, s, keywords: ["burn"]) {
            let nums = Self.numbers(rest)
            guard let kcal = nums.first else { return .issue(.unreadableTimes, "can't read burn: \(s)") }
            let steps = nums.count > 1 ? nums[1] : nil
            return .entry(.burn(kcal: kcal, steps: steps, isEstimate: rest.contains("~")))
        }

        if let m = lower.wholeMatch(of: /steps\s*[:\-]?\s*(~?)\s*([\d,]+)/) {
            return .entry(.steps(Double(m.2.replacingOccurrences(of: ",", with: ""))!, isEstimate: !m.1.isEmpty))
        }
        if let m = lower.wholeMatch(of: /(~?)\s*([\d,]+)\s*steps/) {
            return .entry(.steps(Double(m.2.replacingOccurrences(of: ",", with: ""))!, isEstimate: !m.1.isEmpty))
        }

        // Work: a line that starts with a time range (optionally after "work").
        let workText = Self.afterKeyword(lower, s, keywords: ["work"]) ?? s
        if let r = Self.range(workText) {
            return .entry(.block(Self.forwardBlock(.work, r, on: day, label: r.label)))
        }

        return .entry(.food(Self.food(s)))
    }

    // MARK: Pieces

    struct Range {
        var start: Int
        var end: Int
        var typedMinutes: Int?
        var label: String
        var isEstimate: Bool
    }

    static func forwardBlock(_ kind: BlockKind, _ r: Range, on day: LogicalDay, label: String) -> ParsedBlock {
        let start = WallTime(day: day, minutes: r.start)
        var end = WallTime(day: day, minutes: r.end)
        if r.end < r.start { end.day = day.next } // crosses midnight
        return ParsedBlock(kind: kind, start: start, end: end, label: label, typedMinutes: r.typedMinutes, isEstimate: r.isEstimate)
    }

    /// `0945 - 1045 [1h] > label`, at the start of `s`.
    static func range(_ s: String) -> Range? {
        let pattern = /^\s*~?(\d{1,2}:\d{2}|\d{3,4})\s*(?:-|–|—|to)\s*(\d{1,2}:\d{2}|\d{3,4})(?=\s|$|\[|>)/
        guard let m = s.firstMatch(of: pattern),
              let start = minutes(String(m.1)), let end = minutes(String(m.2)),
              start < 1440
        else { return nil }
        var rest = String(s[m.range.upperBound...])
        // Bracketed durations: the first readable one is the check; others (NC parts) are ignored.
        var typed: Int?
        for b in rest.matches(of: /\[([^\]]*)\]/) {
            if typed == nil { typed = Durations.parseCompact(String(b.1)) }
        }
        rest = rest.replacing(/\[[^\]]*\]/, with: "")
        var label = rest.trimmingCharacters(in: .whitespaces)
        while let f = label.first, ">-:–—".contains(f) { label = String(label.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return Range(start: start, end: end, typedMinutes: typed, label: label, isEstimate: s.contains("~"))
    }

    /// `0945`, `945`, `9:45`, `2400` → minutes after midnight.
    static func minutes(_ t: String) -> Int? {
        let h: Int, m: Int
        if t.contains(":") {
            let p = t.split(separator: ":")
            guard p.count == 2, let hh = Int(p[0]), let mm = Int(p[1]) else { return nil }
            (h, m) = (hh, mm)
        } else {
            guard let n = Int(t) else { return nil }
            (h, m) = (n / 100, n % 100)
        }
        guard m < 60, h < 24 || (h == 24 && m == 0) else { return nil }
        return h * 60 + m
    }

    /// The rest of `original` after a leading keyword and separator (`sleep -> …`, `nc: …`).
    static func afterKeyword(_ lower: String, _ original: String, keywords: [String]) -> String? {
        for k in keywords where lower.hasPrefix(k) {
            let after = lower.dropFirst(k.count)
            guard let next = after.first, !next.isLetter else { continue }
            var rest = String(original.dropFirst(k.count)).trimmingCharacters(in: .whitespaces)
            for sep in ["->", "→", ":", "-", "–", "—"] where rest.hasPrefix(sep) {
                rest = String(rest.dropFirst(sep.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            return rest
        }
        return nil
    }

    /// Every number in `s` (commas as thousands separators).
    static func numbers(_ s: String) -> [Double] {
        s.matches(of: /\d[\d,]*(?:\.\d+)?/).compactMap { Double($0.output.replacingOccurrences(of: ",", with: "")) }
    }

    /// `408 / 8 / 0`, `~1290 / 28 / 0`, `408kcal / 8g` → nutrition (1–3 values) and estimate flag.
    static func values(_ s: String) -> (Nutrition, Bool)? {
        let parts = s.split(separator: "/", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard (1...3).contains(parts.count) else { return nil }
        var nums: [Double] = []
        var estimate = false
        for p in parts {
            guard let m = p.wholeMatch(of: /(~?)\s*(\d+(?:\.\d+)?)\s*(?:kcal|cal|g|gm|mg)?/.ignoresCase()) else { return nil }
            if !m.1.isEmpty { estimate = true }
            nums.append(Double(m.2)!)
        }
        return (Nutrition(kcal: nums[0], proteinG: nums.count > 1 ? nums[1] : nil, caffeineMg: nums.count > 2 ? nums[2] : nil), estimate)
    }

    static func food(_ s: String) -> ParsedFood {
        var text = s
        var timeMinutes: Int?
        if let m = text.prefixMatch(of: /(\d{1,2}:\d{2})\s+/), let t = minutes(String(m.1)), t < 1440 {
            timeMinutes = t
            text = String(text[m.range.upperBound...])
        }
        var estimate = false
        if text.hasPrefix("~") {
            estimate = true
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        var name = text
        var nutrition: Nutrition?
        // Values follow the last " - " (spaced dash) when what follows reads as numbers.
        if let sep = text.ranges(of: /\s+[-–—]\s+/).last,
           let (n, est) = values(String(text[sep.upperBound...])) {
            name = String(text[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
            nutrition = n
            estimate = estimate || est
        }

        var base = name
        var quantity: Double?
        var unit: String?
        let qty = /^(.*?\S)\s*(\d+(?:\.\d+)?)\s*(g|gm|gms|grams?|kg|ml|l|ltr|tsp|tbsp|pcs?|pieces?|cups?|scoops?|slices?)$/.ignoresCase()
        let times = /^(.*?\S)\s+x\s*(\d+(?:\.\d+)?)$/.ignoresCase()
        if let m = name.wholeMatch(of: qty), !m.1.hasSuffix("+"), !m.1.hasSuffix("&") {
            base = String(m.1)
            quantity = Double(m.2)
            unit = Self.canonicalUnit(String(m.3))
        } else if let m = name.wholeMatch(of: times) {
            base = String(m.1)
            quantity = Double(m.2)
            unit = "x"
        }
        return ParsedFood(name: name, baseName: base, quantity: quantity, unit: unit,
                          nutrition: nutrition, timeMinutes: timeMinutes, isEstimate: estimate)
    }

    static func canonicalUnit(_ u: String) -> String {
        switch u.lowercased() {
        case "g", "gm", "gms", "gram", "grams": "g"
        case "l", "ltr": "l"
        case "pc", "pcs", "piece", "pieces": "pc"
        case "cup", "cups": "cup"
        case "scoop", "scoops": "scoop"
        case "slice", "slices": "slice"
        default: u.lowercased()
        }
    }

    static func isIgnorable(_ s: String) -> Bool {
        s.isEmpty || s.hasPrefix("```") || s.hasPrefix("|") || s.hasPrefix("<!--")
            || s.allSatisfy { "-*_=".contains($0) }
    }

    /// Strips heading marks and list bullets.
    static func stripMarkers(_ s: String) -> String {
        var t = Substring(s)
        while t.first == "#" { t = t.dropFirst() }
        t = t.drop(while: \.isWhitespace)
        for bullet in ["- ", "* ", "• ", "+ "] where t.hasPrefix(bullet) {
            t = t.dropFirst(bullet.count)
            break
        }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
