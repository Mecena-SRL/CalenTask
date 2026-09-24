import Foundation
import EventKit
import SwiftData
import Observation

/// EventKit bridge (D10): reads and writes the system calendars — which
/// include any Google/Exchange accounts configured on the device.
///
/// Sync model:
/// - Import: system events become TodoTask(kind: .event) keyed by
///   `eventIdentifier`; the system is the source of truth for events that
///   were created there (remote-newer wins).
/// - Export: .event tasks flow back through the mutation funnel — `touch()`
///   calls `pushIfNeeded` so edits, completions and soft-deletes propagate.
@MainActor @Observable
final class CalendarSyncService {
    static let shared = CalendarSyncService()

    static let syncEnabledKey = "calendarSyncEnabled"

    private let store = EKEventStore()
    /// Suppresses export while we are applying remote changes (no loops).
    private var isApplyingRemote = false

    private(set) var isAuthorized = false
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?

    var isSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.syncEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.syncEnabledKey) }
    }

    private init() {
        isAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // MARK: Authorization

    @discardableResult
    func requestAccessIfNeeded() async -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            isAuthorized = true
            return true
        }
        do {
            isAuthorized = try await store.requestFullAccessToEvents()
        } catch {
            lastError = error.localizedDescription
            isAuthorized = false
        }
        return isAuthorized
    }

    // MARK: Full sync (import + export)

    /// Window kept intentionally wide: a month back, a year ahead.
    private var syncWindow: (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -30, to: .now.startOfDay)!
        let end = calendar.date(byAdding: .day, value: 365, to: .now.startOfDay)!
        return (start, end)
    }

    func syncNow(in context: ModelContext, workspaceID: UUID, createdBy: UUID) async {
        guard await requestAccessIfNeeded() else { return }
        do {
            try importEvents(in: context, workspaceID: workspaceID, createdBy: createdBy)
            try exportUnsyncedEvents(in: context)
            try context.save()
            lastSyncAt = .now
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Import

    private func importEvents(in context: ModelContext, workspaceID: UUID, createdBy: UUID) throws {
        let window = syncWindow
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let events = store.events(matching: predicate)

        isApplyingRemote = true
        defer { isApplyingRemote = false }

        var seenIdentifiers = Set<String>()
        for event in events {
            guard let identifier = event.eventIdentifier else { continue }
            // Recurring events surface once per occurrence; track the series once.
            guard seenIdentifiers.insert(identifier).inserted else { continue }

            let existing = try fetchTask(eventIdentifier: identifier, in: context)
            if let task = existing {
                guard task.deletedAt == nil else { continue }
                let remoteStamp = event.lastModifiedDate ?? .distantPast
                if remoteStamp > task.updatedAt {
                    apply(event, to: task)
                }
            } else {
                let task = TodoTask(
                    workspaceID: workspaceID,
                    title: event.title ?? "Evento",
                    kind: .event,
                    createdByID: createdBy
                )
                context.insert(task)
                apply(event, to: task)
            }
        }

        // Events deleted in the system calendar disappear locally too —
        // but only inside the sync window, and only for already-linked tasks.
        let linked = try fetchLinkedEventTasks(in: context)
        for task in linked where task.deletedAt == nil {
            guard let identifier = task.eventIdentifier,
                  let start = task.startAt,
                  start >= window.start, start <= window.end,
                  !seenIdentifiers.contains(identifier),
                  store.event(withIdentifier: identifier) == nil
            else { continue }
            task.deletedAt = .now
            task.updatedAt = .now
        }
    }

    private func apply(_ event: EKEvent, to task: TodoTask) {
        task.title = event.title ?? task.title
        task.notes = event.notes ?? ""
        task.startAt = event.startDate
        task.endAt = event.endDate
        task.allDay = event.isAllDay
        task.locationName = event.location
        task.videoCallURLString = event.url?.absoluteString
        task.timeZoneID = event.timeZone?.identifier
        task.attendees = (event.attendees ?? []).compactMap(\.name)
        task.alertOffsetsMinutes = (event.alarms ?? []).map { Int(-$0.relativeOffset / 60) }
        task.eventIdentifier = event.eventIdentifier
        task.calendarIdentifier = event.calendar?.calendarIdentifier
        if let rule = event.recurrenceRules?.first {
            task.recurrenceFrequency = RecurrenceFrequency(ekFrequency: rule.frequency)
            task.recurrenceInterval = rule.interval
            task.recurrenceMode = .fixed
            task.recurrenceEndAt = rule.recurrenceEnd?.endDate
        }
        task.updatedAt = .now
    }

    // MARK: Export

    /// .event tasks born in the app (no identifier yet) get pushed on sync.
    private func exportUnsyncedEvents(in context: ModelContext) throws {
        let eventRaw = TaskKind.event.rawValue
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate {
                $0.kindRaw == eventRaw && $0.eventIdentifier == nil
                    && $0.deletedAt == nil && !$0.isTemplate
            }
        )
        for task in try context.fetch(descriptor) where task.startAt != nil {
            try push(task)
        }
    }

    /// Funnel hook: called by `TodoTask.touch()`. Quietly no-ops unless the
    /// task is a synced/syncable event and sync is on.
    func pushIfNeeded(task: TodoTask) {
        guard isSyncEnabled, isAuthorized, !isApplyingRemote,
              task.kind == .event, !task.isTemplate
        else { return }

        // #3 — coalescing: un DatePicker o un drag producono decine di
        // `touch()` al secondo; su EventKit ne arriva uno solo per task,
        // a raffica finita.
        let id = task.id
        pendingPushes[id]?.cancel()
        pendingPushes[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.pendingPushes[id] = nil
            if task.deletedAt != nil {
                self.removeRemoteEvent(for: task)
                return
            }
            guard task.startAt != nil else { return }
            try? self.push(task)
        }
    }

    @ObservationIgnored
    private var pendingPushes: [UUID: Task<Void, Never>] = [:]

    private func push(_ task: TodoTask) throws {
        guard let startAt = task.startAt else { return }
        let event: EKEvent
        if let identifier = task.eventIdentifier,
           let existing = store.event(withIdentifier: identifier) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = task.calendarIdentifier
                .flatMap { store.calendar(withIdentifier: $0) }
                ?? store.defaultCalendarForNewEvents
        }

        event.title = task.title
        event.notes = task.notes.isEmpty ? nil : task.notes
        event.startDate = startAt
        event.endDate = task.endAt ?? startAt.addingTimeInterval(3600)
        event.isAllDay = task.allDay
        event.location = task.locationName
        event.url = task.videoCallURL
        if let timeZoneID = task.timeZoneID {
            event.timeZone = TimeZone(identifier: timeZoneID)
        }
        event.alarms = task.alertOffsetsMinutes.map {
            EKAlarm(relativeOffset: TimeInterval(-$0 * 60))
        }
        if let frequency = task.recurrenceFrequency {
            let end = task.recurrenceEndAt.map { EKRecurrenceEnd(end: $0) }
            event.recurrenceRules = [EKRecurrenceRule(
                recurrenceWith: frequency.ekFrequency,
                interval: max(1, task.recurrenceInterval),
                end: end
            )]
        } else {
            event.recurrenceRules = nil
        }

        try store.save(event, span: .futureEvents)
        if task.eventIdentifier != event.eventIdentifier {
            task.eventIdentifier = event.eventIdentifier
        }
        if task.calendarIdentifier != event.calendar?.calendarIdentifier {
            task.calendarIdentifier = event.calendar?.calendarIdentifier
        }
    }

    private func removeRemoteEvent(for task: TodoTask) {
        guard let identifier = task.eventIdentifier,
              let event = store.event(withIdentifier: identifier)
        else { return }
        try? store.remove(event, span: .futureEvents)
    }

    // MARK: Fetch helpers

    private func fetchTask(eventIdentifier: String, in context: ModelContext) throws -> TodoTask? {
        var descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.eventIdentifier == eventIdentifier }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchLinkedEventTasks(in context: ModelContext) throws -> [TodoTask] {
        let eventRaw = TaskKind.event.rawValue
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.kindRaw == eventRaw && $0.eventIdentifier != nil }
        )
        return try context.fetch(descriptor)
    }
}

extension RecurrenceFrequency {
    var ekFrequency: EKRecurrenceFrequency {
        switch self {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
    }

    init?(ekFrequency: EKRecurrenceFrequency) {
        switch ekFrequency {
        case .daily: self = .daily
        case .weekly: self = .weekly
        case .monthly: self = .monthly
        case .yearly: self = .yearly
        @unknown default: return nil
        }
    }
}
