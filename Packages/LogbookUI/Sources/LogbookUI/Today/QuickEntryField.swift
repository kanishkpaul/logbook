import LogbookImport
import SwiftUI

/// One field that understands the Notes shorthand, with a live preview of what
/// will be saved. Return saves; Escape clears (or closes, via `onDone`).
public struct QuickEntryField: View {
    let model: TodayModel
    var onDone: (() -> Void)?
    @State private var text = ""
    @FocusState private var focused: Bool

    public init(model: TodayModel, text: String = "", onDone: (() -> Void)? = nil) {
        self.model = model
        self.onDone = onDone
        _text = State(initialValue: text)
    }

    private var preview: QuickEntry.Interpretation? { model.interpret(text) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.cursor").foregroundStyle(.secondary)
                TextField("0945-1045 study · pulao 250g · coffee · cig · burn 373 11773 · start sleep", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(save)
                    .onKeyPress(.escape) {
                        if text.isEmpty { onDone?() } else { text = "" }
                        return .handled
                    }
            }
            .padding(10)
            .background(.background.secondary, in: .rect(cornerRadius: 10))

            if let preview, !preview.lines.isEmpty || preview.problem != nil {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(preview.lines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: Self.symbol(line.kind)).foregroundStyle(Self.color(line.kind)).frame(width: 18)
                            Text(line.title).fontWeight(.medium)
                            Text(line.detail).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    if let problem = preview.problem {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else {
                        Text("↩ to save").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 10)
            } else if let confirmation = model.lastConfirmation {
                Label(confirmation, systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary).padding(.horizontal, 10)
            }
        }
        .onAppear { focused = true }
    }

    private func save() {
        guard preview?.canCommit == true else { return }
        if model.submit(text) {
            text = ""
            onDone?()
        }
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "work": Domain.work.symbol
        case "sleep": Domain.sleep.symbol
        case "nature_call": Domain.natureCall.symbol
        case "food": Domain.food.symbol
        case "burn": Domain.energy.symbol
        case "steps": "figure.walk"
        case "timer": "timer"
        case "dictionary": "book"
        default: "circle"
        }
    }

    static func color(_ kind: String) -> Color {
        switch kind {
        case "work": Domain.work.color
        case "sleep": Domain.sleep.color
        case "nature_call": Domain.natureCall.color
        case "food", "dictionary": Domain.food.color
        case "burn", "steps": Domain.energy.color
        default: .secondary
        }
    }
}

#Preview("Quick Entry") {
    QuickEntryField(model: PreviewSupport.todayModel(), text: "paneer 200g - 530 / 36 / 0 / 0 / 2.4c / 40f")
        .padding()
        .frame(width: 560)
}
