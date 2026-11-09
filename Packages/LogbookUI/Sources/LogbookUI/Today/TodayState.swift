import Foundation
import LogbookCore
import LogbookPersistence

/// Everything the Today screen shows, already computed. Views only lay it out.
public struct TodayState: Equatable {
    public var day: LogicalDay
    public var title: String
    public var window: DateInterval
    public var now: Date
    public var heroes: [Hero]
    public var track: [TrackItem]
    public var foodMarks: [FoodMark]
    public var substances: [SubstancePoint]
    public var running: [RunningTimer]
    public var blocks: [BlockRow]
    public var foods: [FoodRow]
    public var samples: [SampleRow]
    public var foodTotals: [NutritionFormat.Part]
    public var closeDay: CloseDayState

    public struct Hero: Equatable, Identifiable {
        public var id: String
        public var domain: Domain
        public var title: String
        public var value: String
        public var unit: String
        /// Neutral comparison, e.g. "40m above your 4-week average".
        public var headline: String?
        /// Extra context, e.g. "1616 in − 373 burn".
        public var detail: String?
        /// Last 14 days; `nil` = not logged (drawn as a gap).
        public var spark: [SparkPoint]
    }

    public struct SparkPoint: Equatable, Identifiable {
        public var day: LogicalDay
        public var value: Double?
        public var id: LogicalDay { day }
    }

    public struct TrackItem: Equatable, Identifiable {
        public var id: UUID
        public var lane: String
        public var domain: Domain
        public var start: Date
        public var end: Date
        public var label: String
        public var isRunning: Bool
    }

    public struct FoodMark: Equatable, Identifiable {
        public var id: UUID
        public var at: Date
        public var name: String
    }

    public struct SubstancePoint: Equatable, Identifiable {
        public var at: Date
        public var substance: Domain
        public var mg: Double
        public var id: String { "\(substance.rawValue)-\(at.timeIntervalSince1970)" }
    }

    public struct RunningTimer: Equatable, Identifiable {
        public var id: UUID
        public var kind: BlockKind
        public var domain: Domain
        public var title: String
        public var start: Date
        /// Running far longer than usual (forgotten-timer guard).
        public var looksForgotten: Bool
    }

    public struct BlockRow: Equatable, Identifiable {
        public var id: UUID
        public var domain: Domain
        public var title: String
        public var times: String
        public var duration: String
        public var isEstimate: Bool
        public var isRunning: Bool
    }

    public struct FoodRow: Equatable, Identifiable {
        public var id: UUID
        public var time: String
        public var name: String
        public var summary: String
        public var needsValues: Bool
        public var isEstimate: Bool
    }

    public struct SampleRow: Equatable, Identifiable {
        public var id: UUID
        public var title: String
        public var value: String
    }
}

public struct CloseDayState: Equatable {
    public var gaps: [Gap]
    public var missingBurn: Bool
    public var missingSteps: Bool
    public var foodsNeedingValues: [TodayState.FoodRow]
    public var summary: [String]

    public struct Gap: Equatable, Identifiable {
        public var interval: DateInterval
        public var text: String
        public var id: Date { interval.start }
    }

    public var isComplete: Bool { gaps.isEmpty && !missingBurn && !missingSteps && foodsNeedingValues.isEmpty }
}
