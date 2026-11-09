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
    /// "7-day average · 1850 kcal · P 92 · C 210 · F 61 (6 days)", once there are 3 logged days.
    public var weekAverage: String?
    public var closeDay: CloseDayState
    public var plan: PlanState = PlanState()

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

/// The plan side of a day: planned blocks (drawn ghosted behind what happened),
/// what's up next, today's tasks and a neutral planned-vs-done line.
public struct PlanState: Equatable {
    public var ghosts: [TodayState.TrackItem] = []
    public var items: [PlanItem] = []
    public var upNext: PlanItem?
    /// "Planned 5h of work · 3h 10m of it happened as planned so far".
    public var summary: String?
    public var tasks: [TaskItem] = []

    public struct PlanItem: Equatable, Identifiable {
        public var id: UUID
        public var domain: Domain
        public var title: String
        public var times: String
        public var duration: String
        public var status: PlanStatus
        public var isNow: Bool
        public var isPast: Bool
        public var start: Date
    }

    public struct TaskItem: Equatable, Identifiable {
        public var id: UUID
        public var title: String
        /// "~45m · 50m spent · due today · #horizon · every Mon"
        public var detail: String
        public var priority: Int
        public var isDone: Bool
        public var isOverdue: Bool
    }
}

public struct CloseDayState: Equatable {
    public var gaps: [Gap]
    public var missingBurn: Bool
    public var missingSteps: Bool
    public var foodsNeedingValues: [TodayState.FoodRow]
    public var summary: [String]
    /// Open tasks from today's list, to move on (tomorrow / someday / drop).
    public var unfinishedTasks: [PlanState.TaskItem] = []
    /// Planned blocks that ended without being marked done or skipped.
    public var unreviewedPlans: [PlanState.PlanItem] = []

    public struct Gap: Equatable, Identifiable {
        public var interval: DateInterval
        public var text: String
        public var id: Date { interval.start }
    }

    public var isComplete: Bool {
        gaps.isEmpty && !missingBurn && !missingSteps && foodsNeedingValues.isEmpty && unfinishedTasks.isEmpty && unreviewedPlans.isEmpty
    }
}
