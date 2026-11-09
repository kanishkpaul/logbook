import LogbookCore
import SwiftUI

/// Running timers with Stop, and Start buttons for kinds not running.
public struct TimersBar: View {
    let model: TodayModel
    @State private var label = ""

    public init(model: TodayModel) {
        self.model = model
    }

    private var running: [TodayState.RunningTimer] { model.state?.running ?? [] }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(running) { timer in
                HStack {
                    RunningTimerLabel(title: timer.title, start: timer.start, domain: timer.domain)
                        .font(.body.monospacedDigit())
                    if timer.looksForgotten {
                        Label("still going?", systemImage: "exclamationmark.circle")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Stop") { model.stopTimer(timer.id) }
                        .help("Stop (⌘. stops all timers)")
                }
            }
            HStack(spacing: 8) {
                TextField("Label (optional)", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                ForEach([BlockKind.work, .sleep, .natureCall], id: \.self) { kind in
                    let domain = Domain(kind: kind)!
                    Button {
                        model.startTimer(kind, label: kind == .work ? label : "")
                        label = ""
                    } label: {
                        Label(domain.title, systemImage: domain.symbol)
                    }
                    .disabled(running.contains { $0.kind == kind })
                    .help("Start a \(domain.title.lowercased()) timer")
                }
            }
            .controlSize(.regular)
        }
    }
}

#Preview("Timers") {
    TimersBar(model: PreviewSupport.todayModel())
        .padding()
        .frame(width: 560)
}
