import LogbookCore
import SwiftUI

/// One semantic hue and SF Symbol per domain, used everywhere (master plan §11).
public enum Domain: String, CaseIterable, Sendable {
    case work, sleep, food, caffeine, nicotine, energy, natureCall, other

    public var color: Color {
        switch self {
        case .work: .indigo
        case .sleep: .purple
        case .food: .orange
        case .caffeine: .brown
        case .nicotine: .gray
        case .energy: .green
        case .natureCall: .teal
        case .other: .mint
        }
    }

    public var symbol: String {
        switch self {
        case .work: "laptopcomputer"
        case .sleep: "bed.double.fill"
        case .food: "fork.knife"
        case .caffeine: "cup.and.saucer.fill"
        case .nicotine: "smoke.fill"
        case .energy: "flame.fill"
        case .natureCall: "drop.fill"
        case .other: "circle.grid.2x2.fill"
        }
    }

    public var title: String {
        switch self {
        case .work: "Work"
        case .sleep: "Sleep"
        case .food: "Food"
        case .caffeine: "Caffeine"
        case .nicotine: "Nicotine"
        case .energy: "Energy"
        case .natureCall: "Nature's call"
        case .other: "Other"
        }
    }

    public init?(kind: BlockKind) {
        switch kind {
        case .work: self = .work
        case .sleep: self = .sleep
        case .natureCall: self = .natureCall
        default: self = .other
        }
    }
}

#Preview("Domains") {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(Domain.allCases, id: \.self) { d in
            Label(d.title, systemImage: d.symbol).foregroundStyle(d.color)
        }
    }
    .padding()
}
