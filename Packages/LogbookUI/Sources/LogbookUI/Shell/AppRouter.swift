import Foundation
import Observation

/// Every screen in the sidebar.
public enum RootScreen: String, Hashable, CaseIterable, Sendable {
    case today, tasks, calendar, review, work, sleep, body, trends, dictionary, importing, data, diagnostics

    public var title: String {
        switch self {
        case .today: "Today"
        case .tasks: "Tasks"
        case .calendar: "Calendar"
        case .review: "Review"
        case .work: "Work"
        case .sleep: "Sleep"
        case .body: "Body"
        case .trends: "Trends"
        case .dictionary: "Dictionary"
        case .importing: "Import"
        case .data: "Backups & Export"
        case .diagnostics: "Diagnostics"
        }
    }

    public var symbol: String {
        switch self {
        case .today: "sun.max"
        case .tasks: "checklist"
        case .calendar: "calendar"
        case .review: "doc.text.magnifyingglass"
        case .work: Domain.work.symbol
        case .sleep: Domain.sleep.symbol
        case .body: "figure.walk"
        case .trends: "chart.xyaxis.line"
        case .dictionary: "book"
        case .importing: "square.and.arrow.down"
        case .data: "externaldrive"
        case .diagnostics: "stethoscope"
        }
    }

    /// ⌘1 … ⌘0 for the first ten screens.
    public var shortcutDigit: Character? {
        guard let i = Self.allCases.firstIndex(of: self), i < 10 else { return nil }
        return Character(String((i + 1) % 10))
    }
}

/// Where the main window is and what it shows on top, shared by menus,
/// the command palette and the sidebar.
@Observable
public final class AppRouter {
    public var screen: RootScreen {
        didSet { UserDefaults.standard.set(screen.rawValue, forKey: "selectedScreen") }
    }
    public var showingPalette = false
    public var showingCloseDay = false

    public init() {
        screen = UserDefaults.standard.string(forKey: "selectedScreen").flatMap(RootScreen.init) ?? .today
    }

    public func go(_ s: RootScreen) {
        screen = s
        showingPalette = false
    }

    public func closeTheDay() {
        screen = .today
        showingPalette = false
        showingCloseDay = true
    }
}
