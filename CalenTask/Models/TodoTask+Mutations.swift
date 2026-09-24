import Foundation
import SwiftData

// Single funnel for task mutations: every change bumps updatedAt
// and keeps scheduled notifications in sync.
extension TodoTask {
    @MainActor
    func toggleDone() {
        setStatus(isDone ? .todo : .done)
    }

    /// Status changes go through here so automations can react (D31).
    @MainActor
    func setStatus(_ newStatus: TaskStatus) {
        guard status != newStatus else { return }
        // #8 — la prossima occorrenza nasce da QUALSIASI completamento
        // (menu Stato, Kanban, pannello Oggi…), non solo dal checkbox.
        if newStatus == .done, hasRecurrence {
            spawnNextOccurrence()
        }
        status = newStatus
        completedAt = newStatus == .done ? .now : nil
        touch()
        if let context = modelContext {
            AutomationEngine.taskChangedStatus(self, in: context)
        }
    }

    @MainActor
    func softDelete() {
        deletedAt = .now
        touch()
    }

    /// Soft-deletes the whole subtree. Deleting a phase takes its children
    /// with it (coherent with the unified tree — see Progettazione/04).
    @MainActor
    func softDeleteSubtree() {
        for child in liveSubtasks {
            child.softDeleteSubtree()
        }
        softDelete()
    }

    @MainActor
    func setDue(_ date: Date?) {
        dueAt = date
        touch()
    }

    /// A3 (audit account): riallinea `workspaceID` al progetto scelto, così
    /// l'invariante task/progetto/spazio non si rompe silenziosamente anche
    /// se un chiamante futuro offrisse un progetto di un altro spazio (oggi i
    /// picker restano nello stesso spazio). Non normalizza ancora il
    /// sottoalbero (sotto-attività, tag, allegati) — trasferimento vero tra
    /// spazi resta un intervento futuro (vedi [[28 - Audit account e collaborazione]]).
    @MainActor
    func move(to project: Project?, parent: TodoTask? = nil) {
        self.project = project
        self.parentTask = parent
        if let project { workspaceID = project.workspaceID }
        touch()
    }

    /// Moves the task along the project pipeline (D29). The automation
    /// engine listens to this transition (D31).
    @MainActor
    func move(toStage stage: WorkflowStage?) {
        guard stageID != stage?.id else { return }
        stageID = stage?.id
        touch()
        if let stage, let context = modelContext {
            AutomationEngine.taskEnteredStage(self, stage: stage, in: context)
        }
    }

    /// Bumps updatedAt, re-syncs notifications and propagates synced events
    /// to the system calendar. The single funnel for every task change.
    @MainActor
    func touch() {
        updatedAt = .now
        NotificationService.shared.sync(task: self)
        CalendarSyncService.shared.pushIfNeeded(task: self)
    }

    // MARK: Recurrence

    /// On completion of a recurring item, create the next occurrence.
    /// `.fixed` advances from the scheduled date; `.afterCompletion` from now.
    @MainActor
    func spawnNextOccurrence() {
        guard let frequency = recurrenceFrequency, let context = modelContext else { return }
        let calendar = Calendar.current

        func next(from date: Date?) -> Date? {
            let anchor: Date
            switch recurrenceMode {
            case .fixed:
                anchor = date ?? .now
            case .afterCompletion:
                // Keep the time-of-day of the original schedule, advance from today.
                let reference = date ?? .now
                let time = calendar.dateComponents([.hour, .minute], from: reference)
                anchor = calendar.date(
                    bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: .now
                ) ?? .now
            }
            return calendar.date(
                byAdding: frequency.calendarComponent, value: max(1, recurrenceInterval), to: anchor
            )
        }

        let nextDue = next(from: dueAt)
        let nextStart = next(from: startAt)
        if let recurrenceEndAt {
            let probe = nextDue ?? nextStart ?? .distantFuture
            guard probe <= recurrenceEndAt else { return }
        }
        let plannedDue = dueAt == nil ? nil : nextDue
        let plannedStart = startAt == nil ? nil : nextStart
        // #8 — completa → riapri → ricompleta non duplica: se la prossima
        // occorrenza esiste già (viva e aperta), non se ne crea un'altra.
        guard !nextOccurrenceExists(due: plannedDue, start: plannedStart, in: context) else {
            return
        }

        let nextTask = TodoTask(
            workspaceID: workspaceID,
            title: title,
            notes: notes,
            kind: kind,
            priority: priority,
            startAt: plannedStart,
            endAt: shiftedEnd(nextStart: nextStart),
            dueAt: plannedDue,
            remindAt: shiftedRemind(calendar: calendar),
            allDay: allDay,
            timeZoneID: timeZoneID,
            locationName: locationName,
            videoCallURLString: videoCallURLString,
            attendees: attendees,
            alertOffsetsMinutes: alertOffsetsMinutes,
            assigneeID: assigneeID,
            isClaimable: isClaimable,
            sortOrder: sortOrder,
            createdByID: createdByID
        )
        nextTask.recurrenceFrequencyRaw = recurrenceFrequencyRaw
        nextTask.recurrenceInterval = recurrenceInterval
        nextTask.recurrenceModeRaw = recurrenceModeRaw
        nextTask.recurrenceEndAt = recurrenceEndAt
        // #8 — la serie non perde pezzi: colore, viaggio, fase della
        // pipeline e tag seguono l'occorrenza successiva.
        nextTask.colorHex = colorHex
        nextTask.travelMinutes = travelMinutes
        nextTask.stageID = stageID
        context.insert(nextTask)
        nextTask.project = project
        nextTask.parentTask = parentTask
        nextTask.tags = tags
        NotificationService.shared.sync(task: nextTask)
    }

    private func nextOccurrenceExists(due: Date?, start: Date?, in context: ModelContext) -> Bool {
        let title = self.title
        let frequencyRaw = recurrenceFrequencyRaw
        let doneRaw = TaskStatus.done.rawValue
        let ownID = id
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate {
            $0.title == title && $0.deletedAt == nil && $0.statusRaw != doneRaw
                && $0.recurrenceFrequencyRaw == frequencyRaw && $0.id != ownID
        })
        let candidates = (try? context.fetch(descriptor)) ?? []
        let projectID = project?.id
        return candidates.contains {
            $0.dueAt == due && $0.startAt == start && $0.project?.id == projectID
        }
    }

    /// Preserves the event duration when the series advances.
    private func shiftedEnd(nextStart: Date?) -> Date? {
        guard let startAt, let endAt, let nextStart else { return nil }
        return nextStart.addingTimeInterval(endAt.timeIntervalSince(startAt))
    }

    /// Preserves the reminder's offset relative to its anchor date.
    private func shiftedRemind(calendar: Calendar) -> Date? {
        guard let remindAt, let frequency = recurrenceFrequency else { return nil }
        return calendar.date(
            byAdding: frequency.calendarComponent, value: max(1, recurrenceInterval), to: remindAt
        )
    }
}
