import LogbookUI
import SwiftUI

@main
struct LogbookApp: App {
    @State private var spike = SpikeModel()

    var body: some Scene {
        Window("Logbook", id: "main") {
            SpikeView(model: spike)
                .task { await spike.refreshAndRecord() }
        }
        .defaultSize(width: 520, height: 560)

        MenuBarExtra {
            MenuBarPanel(model: spike)
        } label: {
            if let start = spike.timerStart {
                RunningTimerLabel(title: spike.timerTitle, start: start)
            } else {
                Image(systemName: "book.closed")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
