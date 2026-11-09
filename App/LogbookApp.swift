import AppKit
import LogbookCore
import LogbookPersistence
import LogbookUI
import SwiftUI

@main
struct LogbookApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("Logbook", id: "main") {
            MainWindow(delegate: delegate)
        }
        .defaultSize(width: 1100, height: 860)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Quick Entry") { delegate.toggleQuickEntry() }
                    .keyboardShortcut("l", modifiers: .command)
            }
        }

        Settings {
            SettingsView(model: delegate.today, quickEntryShortcut: delegate.quickEntryShortcut)
        }
    }
}

/// The main window's content; also hands the delegate a way to reopen it.
private struct MainWindow: View {
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RootView(today: delegate.today, dictionary: delegate.dictionary, data: delegate.data) {
            DiagnosticsView(model: delegate.diagnostics)
        }
        .onAppear { delegate.openMainWindow = { openWindow(id: "main") } }
    }
}

/// Owns the long-lived pieces: the database, models, menu bar item, Quick
/// Entry panel and global hotkey, and the forgotten-timer guard.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: LogStore
    let today: TodayModel
    let dictionary: DictionaryModel
    let data: DataModel
    let diagnostics: DiagnosticsModel
    var openMainWindow: (() -> Void)?
    var quickEntryShortcut: String { hotKey?.active?.label ?? "none (all candidates taken)" }

    private var statusItem: StatusItemController?
    private var quickEntry: QuickEntryPanel?
    private var hotKey: GlobalHotKey?
    private var notifications: NotificationScheduler?
    private var wakeObserver: NSObjectProtocol?

    override init() {
        let store: LogStore
        do {
            store = try AppDatabase.liveStore()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Logbook can't open its database"
            alert.informativeText = "\(error)\n\n\(AppDatabase.defaultDirectory.path)"
            alert.runModal()
            exit(1)
        }
        self.store = store
        today = TodayModel(store: store)
        dictionary = DictionaryModel(store: store)
        data = DataModel(store: store)
        diagnostics = DiagnosticsModel(databaseCheck: { "ok (\(try AppDatabase.tableCount(store.database)) tables)" })

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        today.start()
        statusItem = StatusItemController(today: today, openMain: { [weak self] in self?.showMainWindow() })
        quickEntry = QuickEntryPanel(today: today)
        hotKey = GlobalHotKey { [weak self] in self?.toggleQuickEntry() }
        let scheduler = NotificationScheduler(today: today)
        scheduler.openMain = { [weak self] in self?.showMainWindow() }
        scheduler.start()
        notifications = scheduler
        diagnostics.quickEntryShortcut = quickEntryShortcut

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForgottenTimers() }
        }
        // Daily snapshot now, then check hourly (a new day may start while running).
        data.ensureDaily()
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                self?.data.ensureDaily()
            }
        }
        Task { [weak self] in
            // Let the first snapshot arrive and the status item install.
            try? await Task.sleep(for: .seconds(1.5))
            self?.checkForgottenTimers()
            await self?.diagnostics.refreshAndRecord()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func toggleQuickEntry() {
        quickEntry?.toggle()
    }

    func showMainWindow() {
        NSApplication.shared.activate()
        openMainWindow?()
    }

    /// "Still going?" for timers running far longer than usual (on launch and wake).
    func checkForgottenTimers() {
        for timer in today.forgottenTimers() {
            let alert = NSAlert()
            let elapsed = Durations.compact(Date().timeIntervalSince(timer.start))
            alert.messageText = "\(timer.title) has been running for \(elapsed)"
            alert.informativeText = "Started \(timer.start.formatted(date: .abbreviated, time: .shortened)). Is it still going?"
            alert.addButton(withTitle: "Still going")
            alert.addButton(withTitle: "Stop now")
            alert.addButton(withTitle: "Discard")
            NSApplication.shared.activate()
            switch alert.runModal() {
            case .alertSecondButtonReturn: today.stopTimer(timer.id)
            case .alertThirdButtonReturn: today.discardBlock(timer.id)
            default: break
            }
        }
    }
}
