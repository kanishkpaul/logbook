import Foundation

/// One computed fact a recap may mention. `value` and `comparison` are
/// already formatted by Swift; the language model never sees them, only the
/// label and a direction word, and it can only refer to them by placeholder.
public struct RecapFact: Hashable, Sendable {
    public var id: String
    /// What it is, e.g. "work today".
    public var label: String
    /// Pre-formatted value, e.g. "6h 10m". Inserted verbatim.
    public var value: String
    /// Pre-formatted comparison, e.g. "40m above your 4-week average".
    public var comparison: String?
    /// "higher than usual", "lower than usual", "about usual" or nil.
    public var direction: String?

    public init(id: String, label: String, value: String, comparison: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.comparison = comparison
        if let c = comparison?.lowercased() {
            direction = c.contains("above") || c.contains("more") ? "higher than usual"
                : c.contains("below") || c.contains("less") ? "lower than usual"
                : c.contains("about") ? "about usual" : nil
        }
    }
}

public enum RecapKind: String, Sendable { case daily, weekly }

/// What the model returns (or a test fakes): a headline and up to three points,
/// each naming a fact and phrasing it with `{value}` / `{comparison}` placeholders.
public struct RecapDraft: Hashable, Sendable {
    public struct Point: Hashable, Sendable {
        public var factID: String
        public var phrasing: String
        public init(factID: String, phrasing: String) {
            self.factID = factID
            self.phrasing = phrasing
        }
    }

    public var headline: String
    public var points: [Point]

    public init(headline: String, points: [Point]) {
        self.headline = headline
        self.points = points
    }
}

/// The finished recap shown in the app.
public struct Recap: Hashable, Sendable {
    public enum Source: String, Sendable { case onDevice, template }
    public var headline: String
    public var sentences: [String]
    public var source: Source

    public init(headline: String, sentences: [String], source: Source) {
        self.headline = headline
        self.sentences = sentences
        self.source = source
    }
}

public enum RecapPrompt {
    /// Bump when the wording below changes (cache key).
    public static let version = 4

    /// Kept to three short paragraphs, as Apple suggests for the on-device model.
    public static func instructions(_ kind: RecapKind) -> String {
        """
        You write a short, warm, neutral recap of the user's \(kind == .daily ? "day" : "week") for their private logbook app. \
        You are given facts by id, each with a label and sometimes a direction compared with the user's own usual.

        Write a headline of one short, plain sentence that names what the day held (for example "Work, sleep and a few tasks") \
        and at most three points. Each point names one fact by its id and gives the neutral opening words of a sentence \
        about it, ending right before the number. The app adds the number and any comparison itself, so the opening must \
        not compare or describe amounts.

        Never write digits or numbers yourself, and never use the words more, less, usual, than, felt or effort. Do not \
        guess how the day felt, give advice, praise or blame, or mention health, medicine or reasons why something happened. Avoid the words should, must, cause, risk, good and bad. \
        Example: for a fact "work today", factID "work" and opening "You put in". For "last night's sleep", opening "Last night you slept".
        """
    }

    /// The facts as the model sees them: ids, labels and directions only.
    public static func prompt(_ facts: [RecapFact]) -> String {
        "Facts:\n" + facts.map { f in
            "- id: \(f.id); label: \(f.label)" + (f.direction.map { "; direction: \($0)" } ?? "")
        }.joined(separator: "\n")
    }

    /// Cache key for a fact sheet (prompt version + everything that could change the text).
    public static func cacheKey(_ kind: RecapKind, _ facts: [RecapFact]) -> String {
        "\(version)|\(kind.rawValue)|" + facts.map { "\($0.id)=\($0.value)|\($0.comparison ?? "")" }.joined(separator: ";")
    }
}

/// Checks a model draft and fills in the verified values. Anything off → `nil`.
public enum RecapValidator {
    public enum Problem: Error, Equatable {
        case unknownFact(String)
        case digits(String)
        case bannedWord(String)
        case missingValue(String)
        case comparisonWithoutData(String)
        case tooManyPoints
        case empty
    }

    static let extraBanned = ["diagnose", "healthy", "doctor", "medical", "great job", "well done", "felt", "feel"]
    /// Openings must not compare or judge amounts: the app adds the comparison itself.
    static let openingBanned = ["more", "less", "usual", "than", "effort", "increased", "decreased", "lot", "few", "many", "high", "low"]

    public static func validate(_ draft: RecapDraft, facts: [RecapFact]) throws -> Recap {
        let byID = Dictionary(facts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let headline = draft.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headline.isEmpty, !draft.points.isEmpty else { throw Problem.empty }
        guard draft.points.count <= 3 else { throw Problem.tooManyPoints }
        try check(headline)
        var sentences: [String] = []
        var used = Set<String>()
        for p in draft.points {
            guard let fact = byID[p.factID], used.insert(p.factID).inserted else { throw Problem.unknownFact(p.factID) }
            let text = p.phrasing.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.components(separatedBy: "{value}").count == 2 else { throw Problem.missingValue(text) }
            // An opening is a few neutral words before the number, not a sentence of its own.
            let opening = text.components(separatedBy: "{value}")[0]
            guard opening.split(separator: " ").count <= 8, !opening.contains(where: { ".!?".contains($0) }) else { throw Problem.missingValue(text) }
            let words = opening.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            if let w = words.first(where: { openingBanned.contains($0) }) { throw Problem.bannedWord(w) }
            if text.contains("{comparison}"), fact.comparison == nil { throw Problem.comparisonWithoutData(text) }
            try check(text.replacingOccurrences(of: "{value}", with: "").replacingOccurrences(of: "{comparison}", with: ""))
            var sentence = text
                .replacingOccurrences(of: "{value}", with: fact.value)
                .replacingOccurrences(of: "{comparison}", with: fact.comparison ?? "")
            // The comparison is added by the app when the model didn't place it.
            if let c = fact.comparison, !text.contains("{comparison}") {
                if sentence.hasSuffix(".") { sentence.removeLast() }
                sentence += ", \(c)."
            }
            sentences.append(sentence)
        }
        return Recap(headline: headline, sentences: sentences, source: .onDevice)
    }

    static func check(_ text: String) throws {
        if text.contains(where: \.isNumber) { throw Problem.digits(text) }
        if let word = InsightText.violations(text).first { throw Problem.bannedWord(word) }
        let lower = text.lowercased()
        if let word = extraBanned.first(where: { lower.contains($0) }) { throw Problem.bannedWord(word) }
    }
}

/// The deterministic fallback, used when the model is unavailable or its
/// output doesn't pass validation. Every recap works without AI.
public enum RecapTemplate {
    public static func render(_ kind: RecapKind, _ facts: [RecapFact]) -> Recap {
        let headline = kind == .daily ? "Your day so far" : "Your week"
        let sentences = facts.prefix(4).map { f -> String in
            let label = f.label.prefix(1).uppercased() + f.label.dropFirst()
            return "\(label): \(f.value)" + (f.comparison.map { ", \($0)" } ?? "") + "."
        }
        return Recap(headline: headline, sentences: sentences, source: .template)
    }
}
