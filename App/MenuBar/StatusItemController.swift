import AppKit
import LogbookCore
import Observation
import SwiftUI

/// The menu bar timer, as a plain `NSStatusItem`.
///
/// M0 finding (macOS 27.0.1): a `MenuBarExtra` whose label contains
/// `Text(timerInterval:)` never appears and pins the main thread in a layout
/// loop. So the title is set here once a second from the stored start instant
/// (elapsed = now − start), and the SwiftUI panel lives in a popover.
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let spike: SpikeModel
    private var ticker: Timer?

    init(spike: SpikeModel) {
        self.spike = spike
        super.init()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarPanel(model: spike))
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        observe()
    }

    /// Re-renders whenever the timer starts or stops.
    private func observe() {
        withObservationTracking {
            _ = spike.timerStart
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        render()
    }

    private func render() {
        guard let button = item.button else { return }
        if spike.timerStart != nil {
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "running")?
                .withSymbolConfiguration(.init(pointSize: 7, weight: .regular).applying(.init(paletteColors: [.systemIndigo])))
            startTicking()
        } else {
            button.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: "Logbook")
            button.title = ""
            ticker?.invalidate()
            ticker = nil
        }
        tick()
    }

    private func startTicking() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        // .common keeps it ticking while menus are open.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard let start = spike.timerStart, let button = item.button else { return }
        button.title = " \(spike.timerTitle) \(Durations.clock(Date().timeIntervalSince(start)))"
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
