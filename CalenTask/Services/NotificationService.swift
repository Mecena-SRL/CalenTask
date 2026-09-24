import Foundation
import UserNotifications
import Observation
import SwiftData

/// Schedules and cancels local notifications for tasks.
/// Identifiers per task, all prefixed "task-<id>-": remind (remindAt),
/// due (dueAt), travel ("Parti ora") and alert-<min> (alertOffsetsMinutes).
@MainActor @Observable
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    /// #4 — ultima generazione di piano per task: con modifiche rapide più
    /// `apply` si intrecciano sugli `await`; vince solo il più recente.
    @ObservationIgnored private var generations: [UUID: Int] = [:]
    @ObservationIgnored private var resyncGeneration = 0

    /// Margine sotto il limite iOS di 64 notifiche in attesa (1 va al digest).
    static let maxPendingTaskRequests = 60

    private init() {}

    /// Asks lazily, the first time something actually needs scheduling.
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Re-syncs every trigger from the task's current state. Call after every
    /// mutation that touches title, dates, alerts, status, or deletion.
    func sync(task: TodoTask) {
        // Snapshot value types: @Model instances must not cross into the detached work.
        let plan = NotificationPlan(task: task)
        let generation = (generations[plan.taskID] ?? 0) + 1
        generations[plan.taskID] = generation
        Task { await apply(plan, generation: generation) }
    }

    /// #4 — Riallinea TUTTE le notifiche delle attività aperte: all'avvio e a
    /// ogni ritorno in primo piano. Copre le attività arrivate da iCloud
    /// (create su un altro dispositivo, dove `touch()` non è passato da qui) e
    /// i reinstalli. Tiene solo le più vicine, entro il limite di sistema.
    func resyncAll(in context: ModelContext) {
        guard let tasks = try? context.fetch(
            FetchDescriptor<TodoTask>(predicate: TodoTask.openPredicate)
        ) else { return }
        let now = Date.now
        let planned = tasks
            .flatMap { Self.plannedRequests(for: NotificationPlan(task: $0), now: now) }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(Self.maxPendingTaskRequests)
        resyncGeneration += 1
        let generation = resyncGeneration
        Task {
            let pending = await center.pendingNotificationRequests()
            guard generation == resyncGeneration else { return }
            center.removePendingNotificationRequests(
                withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("task-") }
            )
            guard !planned.isEmpty else { return }
            await requestAuthorizationIfNeeded()
            for item in planned {
                guard generation == resyncGeneration else { return }
                try? await center.add(item.request)
            }
        }
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

    // MARK: Internals

    private struct NotificationPlan {
        let taskID: UUID
        let title: String
        let remindAt: Date?
        let dueAt: Date?
        let startAt: Date?
        let alertOffsetsMinutes: [Int]
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
            alertOffsetsMinutes = task.alertOffsetsMinutes
            travelMinutes = task.travelMinutes
            locationName = task.locationName
            isUrgent = task.priority == .urgent
            isActive = task.deletedAt == nil && !task.isDone && !task.isTemplate
        }
    }

    private struct PlannedRequest {
        let fireDate: Date
        let request: UNNotificationRequest
    }

    private func apply(_ plan: NotificationPlan, generation: Int) async {
        let prefix = Self.taskPrefix(plan.taskID)
        let pending = await center.pendingNotificationRequests()
        guard generations[plan.taskID] == generation else { return }
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        )
        let planned = Self.plannedRequests(for: plan, now: .now)
        guard !planned.isEmpty else { return }

        await requestAuthorizationIfNeeded()
        for item in planned {
            guard generations[plan.taskID] == generation else { return }
            try? await center.add(item.request)
        }
    }

    /// Identificatori e orari che `sync` programmerebbe ora (per i test).
    static func plannedSchedule(for task: TodoTask, now: Date = .now) -> [(id: String, fireDate: Date)] {
        plannedRequests(for: NotificationPlan(task: task), now: now)
            .map { ($0.request.identifier, $0.fireDate) }
    }

    private static func plannedRequests(for plan: NotificationPlan, now: Date) -> [PlannedRequest] {
        guard plan.isActive else { return [] }
        var planned: [PlannedRequest] = []

        func add(id: String, subtitle: String, fireDate: Date, isUrgent: Bool) {
            guard fireDate > now else { return }
            planned.append(PlannedRequest(fireDate: fireDate, request: request(
                id: id,
                subtitle: subtitle,
                body: plan.title,
                taskID: plan.taskID,
                fireDate: fireDate,
                isUrgent: isUrgent
            )))
        }

        if let remindAt = plan.remindAt {
            add(id: remindID(plan.taskID), subtitle: "Promemoria",
                fireDate: remindAt, isUrgent: plan.isUrgent)
        }

        if let dueAt = plan.dueAt {
            add(id: dueID(plan.taskID), subtitle: "Scadenza",
                fireDate: dueFireDate(for: dueAt), isUrgent: plan.isUrgent)
        }

        // #4 — avvisi dell'evento ("15 min prima"): prima erano salvati ed
        // esportati su EventKit ma non notificavano mai.
        if let anchor = plan.startAt ?? plan.dueAt.map(dueFireDate(for:)) {
            for offset in Set(plan.alertOffsetsMinutes).sorted() {
                add(id: alertID(plan.taskID, minutesBefore: offset),
                    subtitle: alertSubtitle(minutesBefore: offset),
                    fireDate: anchor.addingTimeInterval(TimeInterval(-offset * 60)),
                    isUrgent: plan.isUrgent)
            }
        }

        // S5/D63 — "Parti ora": tempo di viaggio prima dell'inizio.
        if let startAt = plan.startAt, plan.travelMinutes > 0 {
            let destination = plan.locationName.map { " → \($0)" } ?? ""
            add(id: travelID(plan.taskID), subtitle: "Parti ora\(destination)",
                fireDate: startAt.addingTimeInterval(TimeInterval(-plan.travelMinutes * 60)),
                isUrgent: true)
        }

        return planned
    }

    private static func request(
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

    static func alertSubtitle(minutesBefore offset: Int) -> String {
        switch offset {
        case ..<1: return "Inizia ora"
        case ..<60: return "Tra \(offset) min"
        case ..<1440 where offset % 60 == 0: return "Tra \(offset / 60) h"
        case ..<1440: return "Tra \(offset / 60) h \(offset % 60) min"
        case _ where offset % 1440 == 0:
            return offset == 1440 ? "Domani" : "Tra \(offset / 1440) giorni"
        default: return "Tra \(offset / 60) h"
        }
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
    static func alertID(_ taskID: UUID, minutesBefore offset: Int) -> String {
        "task-\(taskID.uuidString)-alert-\(offset)"
    }
    static func taskPrefix(_ taskID: UUID) -> String { "task-\(taskID.uuidString)-" }

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
