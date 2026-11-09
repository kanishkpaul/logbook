import AppKit
import LogbookPersistence
import LogbookUI
import Observation
import UserNotifications

/// Keeps macOS's pending notifications equal to what `NotificationPlanner`
/// wants, records them in the notification log (for caps and back-off), and
/// handles their actions (Start / Skip a planned block, Stop a forgotten timer).
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let today: TodayModel
    private let store: LogStore
    private let center = UNUserNotificationCenter.current()
    private var pending: Task<Void, Never>?
    var openMain: () -> Void = {}

    init(today: TodayModel) {
        self.today = today
        self.store = today.store
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "plan-start", actions: [
                UNNotificationAction(identifier: "START", title: "Start", options: []),
                UNNotificationAction(identifier: "SKIP", title: "Skip", options: []),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: "forgotten-timer", actions: [
                UNNotificationAction(identifier: "STOP", title: "Stop now", options: []),
                UNNotificationAction(identifier: "KEEP", title: "Still going", options: []),
            ], intentIdentifiers: []),
        ])
    }

    func start() {
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            await markDelivered()
            observe()
        }
    }

    /// Re-plans a few seconds after anything Today shows changes.
    private func observe() {
        withObservationTracking {
            _ = today.state
            _ = today.insights
            _ = today.enabledNotifications
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    func reschedule() async {
        guard (await center.notificationSettings()).authorizationStatus == .authorized,
              let inputs = try? today.notificationInputs() else { return }
        let wanted = NotificationPlanner().plan(inputs)

        let existing = await center.pendingNotificationRequests()
        let stale = existing.filter { req in
            guard let w = wanted.first(where: { $0.id == req.identifier }) else { return true }
            let fire = (req.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            return fire.map { abs($0.timeIntervalSince(w.fireAt)) > 30 } ?? true
        }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: stale)
        try? store.forgetUnfiredNotifications(after: inputs.now)
        let keep = Set(existing.map(\.identifier)).subtracting(stale)
        for n in wanted {
            try? store.logNotification(id: n.logID, kind: n.kind.rawValue, requested: n.kind.isRequested, fireAt: n.fireAt)
            guard !keep.contains(n.id) else { continue }
            let content = UNMutableNotificationContent()
            content.title = n.title
            content.body = n.body
            content.sound = n.kind.isRequested ? .default : nil
            content.interruptionLevel = n.kind.isRequested ? .active : .passive
            if let c = n.category { content.categoryIdentifier = c }
            var info = n.userInfo
            info["logID"] = n.logID.uuidString
            content.userInfo = info
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: n.fireAt)
            let request = UNNotificationRequest(identifier: n.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(request)
        }
    }

    /// Delivered notifications count toward today's cap (even if not acted on).
    private func markDelivered() async {
        for n in await center.deliveredNotifications() {
            if let raw = n.request.content.userInfo["logID"] as? String, let id = UUID(uuidString: raw) {
                try? store.markNotification(id: id, delivered: n.date)
            }
        }
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let logID = (notification.request.content.userInfo["logID"] as? String).flatMap({ UUID(uuidString: $0) })
        let date = notification.date
        await MainActor.run {
            if let logID { try? self.store.markNotification(id: logID, delivered: date) }
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        func id(_ key: String) -> UUID? { (info[key] as? String).flatMap({ UUID(uuidString: $0) }) }
        let logID = id("logID"), planID = id("planID"), blockID = id("blockID")
        await MainActor.run {
            if let logID { try? self.store.markNotification(id: logID, acted: action) }
            switch action {
            case "START": if let planID { self.today.startPlanned(planID) }
            case "SKIP": if let planID { self.today.skipPlanned(planID) }
            case "STOP": if let blockID { self.today.stopTimer(blockID) }
            case "KEEP": break
            default: self.openMain()
            }
        }
    }
}
