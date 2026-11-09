import EventKit
import Foundation
import LogbookPersistence
import Observation
import ServiceManagement
import UserNotifications

/// M0 spike: checks that an ad-hoc build can run a live menu bar timer and keep
/// notification, login-item and Calendar permissions across rebuilds.
///
/// Each launch writes the current statuses to
/// `~/Library/Application Support/logbook/spike-status.json` (and stdout), so
/// a rebuild-and-relaunch can be compared from the terminal.
@Observable
final class SpikeModel {
    private(set) var notifications = "unknown"
    private(set) var loginItem = "unknown"
    private(set) var calendar = "unknown"
    private(set) var calendarCount: Int?
    private(set) var database = "unknown"
    private(set) var lastError: String?

    /// A running timer is just a stored start instant; elapsed = now − start.
    private(set) var timerStart: Date?
    let timerTitle = "study"

    private let defaults = UserDefaults.standard
    private let eventStore = EKEventStore()

    init() {
        timerStart = defaults.object(forKey: "spike.timerStart") as? Date
    }

    // MARK: Timer

    func toggleTimer() {
        timerStart = timerStart == nil ? Date() : nil
        defaults.set(timerStart, forKey: "spike.timerStart")
    }

    // MARK: Status

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = Self.describe(settings.authorizationStatus)
        loginItem = Self.describe(SMAppService.mainApp.status)
        let cal = EKEventStore.authorizationStatus(for: .event)
        calendar = Self.describe(cal)
        calendarCount = cal == .fullAccess ? eventStore.calendars(for: .event).count : nil
        checkDatabase()
    }

    /// Opens (creating and migrating if needed) the live database. Writes no rows.
    private func checkDatabase() {
        do {
            let db = try AppDatabase.openLive()
            let tables = try AppDatabase.tableCount(db)
            database = "ok (\(tables) tables)"
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
        content.title = "Logbook spike"
        content.body = "Notifications work on this build."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
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
        let exe = Bundle.main.executableURL
        let built = exe.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        let status: [String: String] = [
            "launchedAt": ISO8601DateFormatter().string(from: Date()),
            "binaryBuiltAt": built.map { ISO8601DateFormatter().string(from: $0) } ?? "?",
            "bundlePath": Bundle.main.bundlePath,
            "notifications": notifications,
            "loginItem": loginItem,
            "calendar": calendar,
            "calendarCount": calendarCount.map(String.init) ?? "-",
            "database": database,
        ]
        print("SPIKE", status.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        let dir = URL.applicationSupportDirectory.appending(path: "logbook", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: dir.appending(path: "spike-status.json"))
        } catch {
            lastError = "record: \(error.localizedDescription)"
        }
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
