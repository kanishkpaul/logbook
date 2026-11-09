import SwiftUI

/// "● study 1:12:40" — a self-updating elapsed timer.
///
/// Uses `Text(timerInterval:)`, so the system redraws it and the app has no
/// ticking code. Elapsed time is always `now − start`, so sleep, quit and
/// crash never lose time.
public struct RunningTimerLabel: View {
    let title: String
    let start: Date
    let domain: Domain

    public init(title: String, start: Date, domain: Domain = .work) {
        self.title = title
        self.start = start
        self.domain = domain
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill")
                .foregroundStyle(domain.color)
                .imageScale(.small)
            Text(title)
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) running")
    }
}

#Preview("Running timer") {
    RunningTimerLabel(title: "study", start: .now.addingTimeInterval(-4360))
        .padding()
}
