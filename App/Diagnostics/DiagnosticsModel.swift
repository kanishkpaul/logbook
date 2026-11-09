import AppKit
import EventKit
import Foundation
import LogbookPersistence
import Observation
import ServiceManagement
import UserNotifications

/// Permission and storage checks (from the M0 spike): notifications, login
/// item, Calendar access and the live database.
///
/// Each launch writes the statuses to
/// `~/Library/Application Support/logbook/spike-status.json` (and stdout), so
/// a rebuild-and-relaunch can be compared from the terminal (`make spike-status`).
@Observable
final class DiagnosticsModel {
    private(set) var notifications = "unknown"
    private(set) var loginItem = "unknown"
    private(set) var calendar = "unknown"
    private(set) var calendarCount: Int?
    private(set) var database = "unknown"
    var quickEntryShortcut = "unknown"
    var lastError: String?

    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private let databaseCheck: () throws -> String

    init(databaseCheck: @escaping () throws -> String) {
        self.databaseCheck = databaseCheck
    }

    // MARK: Status

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = Self.describe(settings.authorizationStatus)
        loginItem = Self.describe(SMAppService.mainApp.status)
        let cal = EKEventStore.authorizationStatus(for: .event)
        calendar = Self.describe(cal)
        calendarCount = cal == .fullAccess ? eventStore.calendars(for: .event).count : nil
        do {
            database = try databaseCheck()
        } catch {
            database = "error"
            lastError = "database: \(error)"
        }
    }

    func refreshAndRecord() async {
        await refresh()
        record()
    }

    // MARK: Requests

    func requestNotifications() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            lastError = "notifications: \(error.localizedDescription)"
        }
        await refreshAndRecord()
    }

    func sendTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Logbook"
        content.body = "Notifications work on this build."
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        } catch {
            lastError = "notify: \(error.localizedDescription)"
        }
    }

    func toggleLoginItem() async {
        do {
            if SMAppService.mainApp.status == .enabled {
                try await SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            lastError = "login item: \(error.localizedDescription)"
        }
        await refreshAndRecord()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func requestCalendar() async {
        do {
            _ = try await eventStore.requestFullAccessToEvents()
        } catch {
            lastError = "calendar: \(error.localizedDescription)"
        }
        await refreshAndRecord()
    }

    // MARK: Recording

    private func record() {
        let built = Bundle.main.executableURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        let iso = ISO8601DateFormatter()
        let status: [String: String] = [
            "launchedAt": iso.string(from: Date()),
            "binaryBuiltAt": built.map { iso.string(from: $0) } ?? "?",
            "bundlePath": Bundle.main.bundlePath,
            "notifications": notifications,
            "loginItem": loginItem,
            "calendar": calendar,
            "calendarCount": calendarCount.map(String.init) ?? "-",
            "database": database,
            "statusItemWindows": Self.statusItemWindows(),
            "quickEntryShortcut": quickEntryShortcut,
        ]
        print("SPIKE", status.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        fflush(stdout)
        let dir = AppDatabase.defaultDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: dir.appending(path: "spike-status.json"))
        } catch {
            lastError = "record: \(error.localizedDescription)"
        }
    }

    /// Frames of this app's status-bar windows, to tell "not created" from "hidden".
    static func statusItemWindows() -> String {
        let frames = NSApplication.shared.windows
            .filter { String(describing: type(of: $0)).contains("StatusBar") }
            .map { w in "\(Int(w.frame.minX)),\(Int(w.frame.minY)) \(Int(w.frame.width))x\(Int(w.frame.height)) visible=\(w.isVisible)" }
        return frames.isEmpty ? "none" : frames.joined(separator: "; ")
    }

    // MARK: Descriptions

    static func describe(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        @unknown default: "unknown(\(s.rawValue))"
        }
    }

    static func describe(_ s: SMAppService.Status) -> String {
        switch s {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown(\(s.rawValue))"
        }
    }

    static func describe(_ s: EKAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .fullAccess: "fullAccess"
        case .writeOnly: "writeOnly"
        @unknown default: "unknown(\(s.rawValue))"
        }
    }
}
