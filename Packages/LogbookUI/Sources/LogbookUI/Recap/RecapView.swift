import LogbookCore
import SwiftUI

/// "In short": a recap written on-device from your numbers (or the template).
struct RecapView: View {
    let kind: RecapKind
    let facts: [RecapFact]
    let writer: RecapWriter
    @State private var recap: Recap?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let recap {
                Text(recap.headline).font(.headline)
                ForEach(recap.sentences, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
                Label(recap.source == .onDevice ? "Phrased on this Mac by Apple Intelligence; every number comes from your log."
                                                : "Summary from your log.",
                      systemImage: recap.source == .onDevice ? "sparkles" : "text.alignleft")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: RecapPrompt.cacheKey(kind, facts)) {
            recap = await writer.recap(kind, facts: facts)
        }
    }
}

#Preview("Recap") {
    RecapView(kind: .daily, facts: [RecapFact(id: "work", label: "work today", value: "6h 10m", comparison: "40m above your 4-week average")],
              writer: RecapWriter())
        .padding()
        .frame(width: 520)
}
