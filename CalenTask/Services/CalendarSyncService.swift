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
///   were created there (remote-newer wins). #2 — a recurring series from
///   the calendar becomes one task PER OCCURRENCE (no recurrence of its
///   own); a series pushed by a recurring app task stays that single task.
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
        // In ordine di inizio: la prima occorrenza di ogni serie viene prima.
        let events = store.events(matching: predicate)
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

        isApplyingRemote = true
        defer { isApplyingRemote = false }

        let appSeries = try appOwnedSeries(in: events, context: context)

        var seenKeys = Set<String>()
        for event in events {
            guard let identifier = event.eventIdentifier else { continue }
            // #2 — le serie del calendario si importano occorrenza per
            // occorrenza; quelle di una task ricorrente dell'app una volta sola.
            let isOccurrence = event.hasRecurrenceRules && !appSeries.contains(identifier)
            let key = isOccurrence ? Self.occurrenceKey(for: event) : identifier
            guard seenKeys.insert(key).inserted else { continue }

            if let task = try linkedTask(forKey: key, event: event, isOccurrence: isOccurrence, in: context) {
                guard task.deletedAt == nil else { continue }
                let remoteStamp = event.lastModifiedDate ?? .distantPast
                if remoteStamp > task.updatedAt || (isOccurrence && task.hasRecurrence) {
                    apply(event, to: task, asOccurrence: isOccurrence)
                }
            } else {
                let task = TodoTask(
                    workspaceID: workspaceID,
                    title: event.title ?? "Evento",
                    kind: .event,
                    createdByID: createdBy
                )
                task.source = .imported
                context.insert(task)
                apply(event, to: task, asOccurrence: isOccurrence)
                links.link(event: key, to: task.id)
            }
        }

        // Events deleted in the system calendar disappear locally too —
        // but only inside the sync window, and only for tasks linked ON THIS
        // device (#1): an id imported elsewhere doesn't exist here and does
        // NOT mean "deleted".
        for (key, taskID) in links.links where !seenKeys.contains(key) {
            guard let task = try fetchTask(id: taskID, in: context) else {
                links.unlink(event: key)
                continue
            }
            guard task.deletedAt == nil,
                  let start = task.startAt,
                  start >= window.start, start <= window.end,
                  !remoteEventExists(forKey: key, near: start)
            else { continue }
            task.softDelete()   // funnel: cancels its notifications too
            links.unlink(event: key)
        }
    }

    /// #2 — Le serie ricorrenti di una task ricorrente dell'APP (creata qui e
    /// spinta nel calendario) restano quella task. Le serie importate col
    /// codice vecchio (una task per tutta la serie) passano all'occorrenza
    /// che mostravano; le altre occorrenze arrivano con l'import.
    private func appOwnedSeries(in events: [EKEvent], context: ModelContext) throws -> Set<String> {
        var owned = Set<String>()
        var checked = Set<String>()
        for event in events where event.hasRecurrenceRules {
            guard let identifier = event.eventIdentifier,
                  checked.insert(identifier).inserted,
                  let task = try seriesTask(for: identifier, in: context)
            else { continue }
            if Self.isAppOwnedSeries(
                taskSource: task.source, taskCreatedAt: task.createdAt, eventCreatedAt: event.creationDate
            ) {
                owned.insert(identifier)
                continue
            }
            let target = events.first {
                $0.eventIdentifier == identifier && $0.startDate == task.startAt
            } ?? event
            links.unlink(event: identifier)
            links.link(event: Self.occurrenceKey(for: target), to: task.id)
            if task.deletedAt == nil { apply(target, to: task, asOccurrence: true) }
        }
        return owned
    }

    /// La task legata a una serie per id (registro o, prima del registro,
    /// l'id salvato), escluse le occorrenze importate.
    private func seriesTask(for identifier: String, in context: ModelContext) throws -> TodoTask? {
        if let taskID = links.taskID(forEvent: identifier) {
            return try fetchTask(id: taskID, in: context)
        }
        let importedRaw = TaskSource.imported.rawValue
        var descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate {
            $0.eventIdentifier == identifier && $0.sourceRaw != importedRaw
        })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// #2 — Una serie è "dell'app" se la task non viene da un import ed è
    /// nata PRIMA dell'evento (l'app l'ha creata e poi spinta nel
    /// calendario). Le task importate dal codice vecchio non hanno la
    /// provenienza, ma sono nate dopo l'evento di sistema. Senza data
    /// dell'evento non si migra nulla.
    static func isAppOwnedSeries(taskSource: TaskSource, taskCreatedAt: Date, eventCreatedAt: Date?) -> Bool {
        guard taskSource != .imported else { return false }
        guard let eventCreatedAt else { return true }
        return eventCreatedAt >= taskCreatedAt
    }

    static func occurrenceKey(for event: EKEvent) -> String {
        let series: String? = event.calendarItemExternalIdentifier
        let identifier: String? = event.eventIdentifier
        let original: Date? = event.occurrenceDate
        let start: Date? = event.startDate
        return EventLinkRegistry.occurrenceKey(
            series: series ?? identifier ?? "",
            occurrenceDate: original ?? start ?? .distantPast
        )
    }

    /// #2 — L'occorrenza precisa di una serie: per id EventKit restituisce
    /// solo la prima. Si cerca vicino alla data originale e a `hint` (l'ultima
    /// data nota, se l'occorrenza è stata spostata).
    private func occurrence(series: String, at occurrenceDate: Date, near hint: Date?) -> EKEvent? {
        let calendar = Calendar.current
        let from = min(occurrenceDate, hint ?? occurrenceDate)
        let to = max(occurrenceDate, hint ?? occurrenceDate)
        guard let start = calendar.date(byAdding: .day, value: -1, to: from),
              let end = calendar.date(byAdding: .day, value: 1, to: to)
        else { return nil }
        let target = EventLinkRegistry.occurrenceKey(series: series, occurrenceDate: occurrenceDate)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).first { Self.occurrenceKey(for: $0) == target }
    }

    private func remoteEventExists(forKey key: String, near hint: Date?) -> Bool {
        if let occurrence = EventLinkRegistry.occurrence(fromKey: key) {
            return self.occurrence(series: occurrence.series, at: occurrence.date, near: hint) != nil
        }
        return store.event(withIdentifier: key) != nil
    }

    /// The task for a LOCAL event: 1) this device's registry; 2) a task
    /// created here before the registry existed; 3) the same meeting already
    /// imported by another device (same title and times, not linked here) —
    /// adopted instead of duplicated (#1).
    private func linkedTask(
        forKey key: String, event: EKEvent, isOccurrence: Bool, in context: ModelContext
    ) throws -> TodoTask? {
        if let taskID = links.taskID(forEvent: key) {
            if let task = try fetchTask(id: taskID, in: context) { return task }
            links.unlink(event: key)
        }
        // #2 — le occorrenze condividono l'id: il legame per id vale solo
        // per gli eventi singoli.
        if !isOccurrence, let task = try fetchTask(eventIdentifier: key, in: context) {
            links.link(event: key, to: task.id)
            return task
        }
        if let task = try adoptableTask(for: event, in: context) {
            links.link(event: key, to: task.id)
            return task
        }
        return nil
    }

    private func adoptableTask(for event: EKEvent, in context: ModelContext) throws -> TodoTask? {
        let start: Date? = event.startDate
        guard start != nil else { return nil }
        let end: Date? = event.endDate
        let title = event.title ?? "Evento"
        let eventRaw = TaskKind.event.rawValue
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate {
            $0.kindRaw == eventRaw && $0.deletedAt == nil && $0.eventIdentifier != nil
                && $0.title == title && $0.startAt == start
        })
        return try context.fetch(descriptor).first { task in
            task.endAt == end && !links.isLinkedHere(task.id)
        }
    }

    /// This device's EKEvent for a task, if any, with the span to edit it.
    /// #2 — for an occurrence of a calendar series: that occurrence only
    /// (`.thisEvent`); never the whole series.
    private func localEvent(for task: TodoTask) -> (event: EKEvent, span: EKSpan)? {
        if let key = links.eventIdentifier(forTask: task.id) {
            if let occurrence = EventLinkRegistry.occurrence(fromKey: key) {
                return self.occurrence(series: occurrence.series, at: occurrence.date, near: task.startAt)
                    .map { ($0, .thisEvent) }
            }
            if let event = store.event(withIdentifier: key) { return (event, .futureEvents) }
        }
        // Una serie ritrovata per id appartiene solo a una task ricorrente.
        if let identifier = task.eventIdentifier,
           let event = store.event(withIdentifier: identifier),
           !event.hasRecurrenceRules || task.hasRecurrence {
            links.link(event: identifier, to: task.id)
            return (event, .futureEvents)
        }
        return nil
    }

    private func apply(_ event: EKEvent, to task: TodoTask, asOccurrence: Bool) {
        task.title = event.title ?? task.title
        // #2 — le note scritte nell'app non si perdono.
        task.notes = Self.mergedNotes(local: task.notes, remote: event.notes)
        task.startAt = event.startDate
        task.endAt = event.endDate
        task.allDay = event.isAllDay
        task.locationName = event.location
        task.videoCallURLString = event.url?.absoluteString
        task.timeZoneID = event.timeZone?.identifier
        task.attendees = (event.attendees ?? []).compactMap(\.name)
        task.alertOffsetsMinutes = (event.alarms ?? []).map { Int(-$0.relativeOffset / 60) }
        // #1 — device-local ids: set once (new task), never overwritten by
        // another device's import.
        if task.eventIdentifier == nil { task.eventIdentifier = event.eventIdentifier }
        if task.calendarIdentifier == nil {
            task.calendarIdentifier = event.calendar?.calendarIdentifier
        }
        if asOccurrence {
            // #2 — la serie la governa il calendario: l'occorrenza non
            // ricorre anche nell'app (al completamento niente copie).
            task.recurrenceFrequency = nil
            task.recurrenceEndAt = nil
            task.source = .imported
        } else if let rule = event.recurrenceRules?.first {
            task.recurrenceFrequency = RecurrenceFrequency(ekFrequency: rule.frequency)
            task.recurrenceInterval = rule.interval
            task.recurrenceMode = .fixed
            task.recurrenceEndAt = rule.recurrenceEnd?.endDate
        }
        task.updatedAt = .now
    }

    /// #2 — Unisce invece di sovrascrivere: se un testo contiene l'altro
    /// vince il più completo, altrimenti si tengono entrambi. Nel dubbio
    /// si conserva (una nota svuotata altrove non cancella quella locale).
    static func mergedNotes(local: String, remote: String?) -> String {
        let remote = remote ?? ""
        let localText = local.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteText = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if remoteText.isEmpty || localText.contains(remoteText) { return local }
        if localText.isEmpty || remoteText.contains(localText) { return remote }
        return local + "\n\n" + remote
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

    /// #1 — this device's own event ↔ task links (never synced).
    @ObservationIgnored
    private var links = EventLinkRegistry()

    private func push(_ task: TodoTask) throws {
        guard let startAt = task.startAt else { return }
        let event: EKEvent
        let span: EKSpan
        let linkedKey = links.eventIdentifier(forTask: task.id)
        if let existing = localEvent(for: task) {
            event = existing.event
            span = existing.span
        } else if linkedKey.flatMap(EventLinkRegistry.occurrence(fromKey:)) != nil
                    || (task.eventIdentifier != nil && linkedKey == nil) {
            // #1 — linked to ANOTHER device's event that isn't here (yet), or
            // #2 an occurrence not found: a new event would be a duplicate.
            return
        } else {
            span = .futureEvents
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
        // #2 — un'occorrenza non cambia la regola della serie.
        if span == .futureEvents {
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
        }

        try store.save(event, span: span)
        if span == .futureEvents, let identifier = event.eventIdentifier {
            links.link(event: identifier, to: task.id)
        }
        // Synced fields only mark "linked somewhere": written once, never
        // overwritten with this device's ids (no ping-pong between devices).
        if task.eventIdentifier == nil {
            task.eventIdentifier = event.eventIdentifier
        }
        if task.calendarIdentifier == nil {
            task.calendarIdentifier = event.calendar?.calendarIdentifier
        }
    }

    private func removeRemoteEvent(for task: TodoTask) {
        guard let local = localEvent(for: task) else { return }
        let key = links.eventIdentifier(forTask: task.id)
        try? store.remove(local.event, span: local.span)   // #2 — un'occorrenza: solo lei
        if let key { links.unlink(event: key) }
    }

    // MARK: Fetch helpers

    private func fetchTask(eventIdentifier: String, in context: ModelContext) throws -> TodoTask? {
        var descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.eventIdentifier == eventIdentifier }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchTask(id: UUID, in context: ModelContext) throws -> TodoTask? {
        var descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
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
