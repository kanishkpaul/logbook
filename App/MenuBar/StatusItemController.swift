import AppKit
import LogbookCore
import LogbookUI
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
    private let today: TodayModel
    private var ticker: Timer?

    init(today: TodayModel, openMain: @escaping () -> Void) {
        self.today = today
        super.init()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarPanel(
            model: today,
            openMain: { [weak popover] in
                popover?.performClose(nil)
                openMain()
            },
            quit: { NSApplication.shared.terminate(nil) }
        ))
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.toolTip = "Logbook"
        }
        observe()
    }

    /// Re-renders whenever the set of running timers changes.
    private func observe() {
        withObservationTracking {
            _ = today.state?.running
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        render()
    }

    /// The timer shown in the bar: work first, then whatever started first.
    private var shown: TodayState.RunningTimer? {
        let running = today.state?.running ?? []
        return running.first { $0.kind == .work } ?? running.first
    }

    private func render() {
        guard let button = item.button else { return }
        if let timer = shown {
            let color = NSColor(timer.domain.color)
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "running")?
                .withSymbolConfiguration(.init(pointSize: 7, weight: .regular).applying(.init(paletteColors: [color])))
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
        guard let timer = shown, let button = item.button else { return }
        let extra = (today.state?.running.count ?? 1) > 1 ? " +\((today.state?.running.count ?? 1) - 1)" : ""
        button.title = " \(timer.title) \(Durations.clock(Date().timeIntervalSince(timer.start)))\(extra)"
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
