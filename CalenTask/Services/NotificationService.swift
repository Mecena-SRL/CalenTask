import Foundation
import UserNotifications
import Observation

/// Schedules and cancels local notifications for tasks.
/// Two identifiers per task: "task-<id>-remind" (remindAt) and "task-<id>-due" (dueAt).
@MainActor @Observable
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// Asks lazily, the first time something actually needs scheduling.
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Re-syncs both triggers from the task's current state. Call after every
    /// mutation that touches title, dates, status, or deletion.
    func sync(task: TodoTask) {
        // Snapshot value types: @Model instances must not cross into the detached work.
        let plan = NotificationPlan(task: task)
        Task { await apply(plan) }
    }

    /// Immediate banner from the automation engine (D31).
    func postAutomationNotice(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "automation-\(UUID().uuidString)", content: content, trigger: nil
        )
        Task {
            await requestAuthorizationIfNeeded()
            try? await center.add(request)
        }
    }

    func cancelAll(for taskID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: [
                Self.remindID(taskID), Self.dueID(taskID), Self.travelID(taskID),
            ]
        )
    }

    // MARK: Internals

    private struct NotificationPlan {
        let taskID: UUID
        let title: String
        let remindAt: Date?
        let dueAt: Date?
        let startAt: Date?
        let travelMinutes: Int
        let locationName: String?
        let isUrgent: Bool
        let isActive: Bool

        init(task: TodoTask) {
            taskID = task.id
            title = task.title
            remindAt = task.remindAt
            dueAt = task.dueAt
            startAt = task.startAt
            travelMinutes = task.travelMinutes
            locationName = task.locationName
            isUrgent = task.priority == .urgent
            isActive = task.deletedAt == nil && !task.isDone
        }
    }

    private func apply(_ plan: NotificationPlan) async {
        cancelAll(for: plan.taskID)
        guard plan.isActive else { return }

        var requests: [UNNotificationRequest] = []
        if let remindAt = plan.remindAt, remindAt > .now {
            requests.append(request(
                id: Self.remindID(plan.taskID),
                subtitle: "Promemoria",
                body: plan.title,
                taskID: plan.taskID,
                fireDate: remindAt,
                isUrgent: plan.isUrgent
            ))
        }
        if let dueAt = plan.dueAt {
            let fireDate = Self.dueFireDate(for: dueAt)
            if fireDate > .now {
                requests.append(request(
                    id: Self.dueID(plan.taskID),
                    subtitle: "Scadenza",
                    body: plan.title,
                    taskID: plan.taskID,
                    fireDate: fireDate,
                    isUrgent: plan.isUrgent
                ))
            }
        }
        // S5/D63 — "Parti ora": tempo di viaggio prima dell'inizio.
        if let startAt = plan.startAt, plan.travelMinutes > 0 {
            let fireDate = startAt.addingTimeInterval(TimeInterval(-plan.travelMinutes * 60))
            if fireDate > .now {
                let destination = plan.locationName.map { " → \($0)" } ?? ""
                requests.append(request(
                    id: Self.travelID(plan.taskID),
                    subtitle: "Parti ora\(destination)",
                    body: plan.title,
                    taskID: plan.taskID,
                    fireDate: fireDate,
                    isUrgent: true
                ))
            }
        }
        guard !requests.isEmpty else { return }

        await requestAuthorizationIfNeeded()
        for request in requests {
            try? await center.add(request)
        }
    }

    private func request(
        id: String, subtitle: String, body: String, taskID: UUID, fireDate: Date,
        isUrgent: Bool = false
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = subtitle
        content.body = body
        content.sound = .default
        // S5 — le urgenze bucano i Focus (time-sensitive, mai "critical":
        // quello richiede un entitlement speciale di Apple).
        content.interruptionLevel = isUrgent ? .timeSensitive : .active
        content.userInfo = ["taskID": taskID.uuidString]
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// Deadlines set via date chips land at midnight; notify at 09:00 instead.
    static func dueFireDate(for dueAt: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: dueAt)
        if components.hour == 0 && components.minute == 0 {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueAt) ?? dueAt
        }
        return dueAt
    }

    static func remindID(_ taskID: UUID) -> String { "task-\(taskID.uuidString)-remind" }
    static func dueID(_ taskID: UUID) -> String { "task-\(taskID.uuidString)-due" }
    static func travelID(_ taskID: UUID) -> String { "task-\(taskID.uuidString)-travel" }

    // MARK: Digest giornaliero (S6/D67) — UNA notifica, silenziosa, alle 8

    static let digestEnabledKey = "dailyDigestEnabled"
    private static let digestID = "daily-digest"

    /// Riprogramma il digest del mattino con i numeri attuali. Da chiamare
    /// quando l'app va in background (i dati sono freschi di sessione).
    func scheduleDailyDigest(events: Int, deadlines: Int, overdue: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.digestID])
        let enabled = UserDefaults.standard.object(forKey: Self.digestEnabledKey) as? Bool ?? true
        guard enabled, events + deadlines + overdue > 0 else { return }

        let calendar = Calendar.current
        guard var fireDate = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: .now)
        else { return }
        if fireDate <= .now {
            fireDate = calendar.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
        }

        var parts: [String] = []
        if events > 0 { parts.append("\(events) event\(events == 1 ? "o" : "i")") }
        if deadlines > 0 { parts.append("\(deadlines) scadenz\(deadlines == 1 ? "a" : "e")") }
        if overdue > 0 { parts.append("\(overdue) in ritardo") }

        let content = UNMutableNotificationContent()
        content.title = "Il tuo giorno"
        content.body = parts.joined(separator: " · ")
        content.interruptionLevel = .passive   // silenzioso: informa, non disturba
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate
        )
        let request = UNNotificationRequest(
            identifier: Self.digestID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        Task {
            await requestAuthorizationIfNeeded()
            try? await center.add(request)
        }
    }
}
