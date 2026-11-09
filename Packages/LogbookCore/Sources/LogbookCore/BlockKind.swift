import Foundation

/// What a time block records. Open-ended so custom kinds (gym, commute…) can be
/// added later without a schema change; stored as its raw string.
public struct BlockKind: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let work = BlockKind(rawValue: "work")
    public static let sleep = BlockKind(rawValue: "sleep")
    public static let natureCall = BlockKind(rawValue: "nature_call")

    public var description: String { rawValue }

    /// Which end of a block decides the logical day its total counts toward.
    public var attributionRule: AttributionRule {
        self == .sleep ? .endDay : .startDay
    }
}

/// How a block is assigned to one logical day for daily totals.
public enum AttributionRule: Sendable {
    /// The day containing the block's start (work, nature's call, custom kinds).
    case startDay
    /// The day containing the block's end, i.e. the day you wake up (sleep).
    case endDay
}

public enum Attribution {
    /// The logical day a block's whole duration counts toward.
    ///
    /// The result is meant to be stored on the row when it is written (and
    /// re-computed only when the block itself is edited, e.g. a running timer
    /// is stopped). A running block (`end == nil`) is provisionally attributed
    /// by its start.
    ///
    /// `timeZone` is the zone the anchor instant happened in; a block started in
    /// one zone and ended in another still has an exact duration (`end − start`).
    public static func day(
        kind: BlockKind,
        start: Date,
        end: Date?,
        boundary: DayBoundary,
        timeZone: TimeZone
    ) -> LogicalDay {
        let anchor: Date = switch kind.attributionRule {
        case .startDay: start
        case .endDay: end ?? start
        }
        return boundary.logicalDay(containing: anchor, in: timeZone)
    }
}

/// Where a row came from. Stored as its raw string.
public enum Source: String, Sendable, Codable, CaseIterable {
    case manual
    case timer
    case `import`
    case plan
}
