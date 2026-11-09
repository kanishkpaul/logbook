import SwiftUI

/// One-click logging: favourites and frequent recents, plus "Copy yesterday".
/// Each button goes through Quick Entry, so the dictionary and meals apply.
struct QuickAddBar: View {
    let model: TodayModel

    var body: some View {
        if !model.quickAdd.isEmpty || model.yesterdayFoodCount > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.quickAdd, id: \.self) { name in
                        Button(name) { model.submit(name) }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .help("Log \(name) now")
                    }
                    if model.yesterdayFoodCount > 0 {
                        Button {
                            model.submit("copy yesterday")
                        } label: {
                            Label("Copy yesterday (\(model.yesterdayFoodCount))", systemImage: "arrow.uturn.down")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .help("Log yesterday's food again at the same times")
                    }
                }
            }
            .controlSize(.small)
        }
    }
}

#Preview("Quick add") {
    QuickAddBar(model: PreviewSupport.todayModel())
        .padding()
        .frame(width: 600)
}
