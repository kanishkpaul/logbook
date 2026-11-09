import Foundation
import FoundationModels
import LogbookCore
import Observation

/// Something that can turn a fact sheet into a draft (the on-device model, or a fake in tests).
public protocol RecapModel: Sendable {
    var isAvailable: Bool { get }
    func draft(instructions: String, prompt: String) async throws -> RecapDraft
}

/// Apple's on-device model through Foundation Models: free, offline, private.
/// A fresh session per recap; structured output via `@Generable`.
public struct OnDeviceRecapModel: RecapModel {
    public init() {}

    public var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    public func draft(instructions: String, prompt: String) async throws -> RecapDraft {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: GeneratedRecap.self)
        // The model writes the words before the number; the value goes after them.
        return RecapDraft(headline: response.content.headline,
                          points: response.content.points.map { .init(factID: $0.factID, phrasing: "\($0.opening.trimmingCharacters(in: .whitespaces)) {value}.") })
    }
}

@Generable
nonisolated struct GeneratedRecap {
    // Constrained decoding: letters and punctuation only, so no numbers can appear.
    @Guide(description: "One short, neutral sentence about the period. No numbers.")
    var headline: String
    @Guide(description: "At most three points, each about one fact.", .maximumCount(3))
    var points: [GeneratedPoint]
}

@Generable
nonisolated struct GeneratedPoint {
    @Guide(description: "The id of the fact this point is about, exactly as given.")
    var factID: String
    @Guide(description: "The first few words of a sentence about this fact, ending right before the number the app will add. For example: You put in")
    var opening: String
}

/// Writes recaps: on-device model first (validated, one retry), template otherwise.
/// Results are cached by fact sheet, so the same numbers give the same text.
@Observable
public final class RecapWriter {
    public let model: any RecapModel
    public var useOnDeviceModel: Bool {
        didSet { UserDefaults.standard.set(useOnDeviceModel, forKey: "useOnDeviceRecap") }
    }
    @ObservationIgnored private var cache: [String: Recap] = [:]
    /// How many model calls were made (for tests and Diagnostics).
    public private(set) var modelCalls = 0

    public init(model: any RecapModel = OnDeviceRecapModel()) {
        self.model = model
        useOnDeviceModel = UserDefaults.standard.object(forKey: "useOnDeviceRecap") as? Bool ?? true
    }

    public var modelAvailable: Bool { model.isAvailable }

    public func recap(_ kind: RecapKind, facts: [RecapFact]) async -> Recap {
        guard !facts.isEmpty else { return Recap(headline: kind == .daily ? "Nothing logged yet" : "Nothing logged this week", sentences: [], source: .template) }
        let key = RecapPrompt.cacheKey(kind, facts) + (useOnDeviceModel ? "|ai" : "|t")
        if let cached = cache[key] { return cached }
        var result = RecapTemplate.render(kind, facts)
        if useOnDeviceModel, model.isAvailable {
            for _ in 0..<2 {
                modelCalls += 1
                guard let draft = try? await model.draft(instructions: RecapPrompt.instructions(kind), prompt: RecapPrompt.prompt(facts)),
                      let checked = try? RecapValidator.validate(draft, facts: facts) else { continue }
                result = checked
                break
            }
        }
        cache[key] = result
        return result
    }
}
