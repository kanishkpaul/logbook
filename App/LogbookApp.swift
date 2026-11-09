import AppKit
import LogbookUI
import SwiftUI

@main
struct LogbookApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("Logbook", id: "main") {
            SpikeView(model: delegate.spike)
                .task { await delegate.spike.refreshAndRecord() }
        }
        .defaultSize(width: 520, height: 560)
    }
}

/// Owns the long-lived pieces: the spike model and the menu bar status item.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let spike = SpikeModel()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(spike: spike)
        Task { [spike] in
            // Record after the status item is installed, so its frame is captured.
            try? await Task.sleep(for: .seconds(1))
            await spike.refreshAndRecord()
        }
    }
}
