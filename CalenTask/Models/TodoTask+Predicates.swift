import Foundation
import SwiftData

// #5 — Predicati di dominio riusabili, filtrati nello STORE (non in memoria).
// `workspaceID == nil` ⇒ tutti gli spazi.
extension TodoTask {
    /// Aperte: non cancellate, non completate, niente fasi né modelli.
    static var openPredicate: Predicate<TodoTask> { openPredicate(workspaceID: nil) }

    /// Inbox = no project, not deleted, not done. Phases and templates never
    /// surface here (they are containers/blueprints, not actionable items).
    static var inboxPredicate: Predicate<TodoTask> { inboxPredicate(workspaceID: nil) }

    static func openPredicate(workspaceID: UUID?) -> Predicate<TodoTask> {
        let doneRaw = TaskStatus.done.rawValue
        let phaseRaw = TaskKind.phase.rawValue
        guard let workspaceID else {
            return #Predicate<TodoTask> { task in
                task.deletedAt == nil && task.statusRaw != doneRaw
                    && task.kindRaw != phaseRaw && !task.isTemplate
            }
        }
        return #Predicate<TodoTask> { task in
            task.workspaceID == workspaceID && task.deletedAt == nil
                && task.statusRaw != doneRaw && task.kindRaw != phaseRaw && !task.isTemplate
        }
    }

    static func inboxPredicate(workspaceID: UUID?) -> Predicate<TodoTask> {
        let doneRaw = TaskStatus.done.rawValue
        let phaseRaw = TaskKind.phase.rawValue
        guard let workspaceID else {
            return #Predicate<TodoTask> { task in
                task.project == nil && task.deletedAt == nil && task.statusRaw != doneRaw
                    && task.kindRaw != phaseRaw && !task.isTemplate
            }
        }
        return #Predicate<TodoTask> { task in
            task.workspaceID == workspaceID && task.project == nil && task.deletedAt == nil
                && task.statusRaw != doneRaw && task.kindRaw != phaseRaw && !task.isTemplate
        }
    }

    // MARK: Finestra del calendario
    //
    // Predicati piccoli, una query ciascuno: un unico predicato con `??` a
    // catena supera il limite del type-checker.

    /// Tutto ciò che il calendario mostra in [start, end), da unire con
    /// `mergingUnique`: inizio nella finestra, eventi iniziati prima che ci
    /// arrivano, scadenze, fasi che la attraversano, aperte senza date.
    static func calendarWindowPredicates(from start: Date, to end: Date, workspaceID: UUID?) -> [Predicate<TodoTask>] {
        [
            calendarStartPredicate(from: start, to: end, workspaceID: workspaceID),
            calendarOngoingPredicate(from: start, workspaceID: workspaceID),
            calendarDuePredicate(from: start, to: end, workspaceID: workspaceID),
            calendarSpanningPredicate(from: start, to: end, workspaceID: workspaceID),
            unscheduledPredicate(workspaceID: workspaceID),
        ]
    }

    /// Inizio in [start, end).
    static func calendarStartPredicate(from start: Date, to end: Date, workspaceID: UUID?) -> Predicate<TodoTask> {
        let past = Date.distantPast
        let future = Date.distantFuture
        let anyWorkspace = workspaceID == nil
        let workspace = workspaceID ?? UUID()
        return #Predicate<TodoTask> { task in
            task.deletedAt == nil && !task.isTemplate
                && (anyWorkspace || task.workspaceID == workspace)
                && (task.startAt ?? past) >= start && (task.startAt ?? future) < end
        }
    }

    /// Iniziati prima della finestra e ancora in corso (eventi su più giorni).
    static func calendarOngoingPredicate(from start: Date, workspaceID: UUID?) -> Predicate<TodoTask> {
        let past = Date.distantPast
        let future = Date.distantFuture
        let anyWorkspace = workspaceID == nil
        let workspace = workspaceID ?? UUID()
        return #Predicate<TodoTask> { task in
            task.deletedAt == nil && !task.isTemplate
                && (anyWorkspace || task.workspaceID == workspace)
                && (task.startAt ?? future) < start && (task.endAt ?? past) >= start
        }
    }

    /// Scadenza in [start, end).
    static func calendarDuePredicate(from start: Date, to end: Date, workspaceID: UUID?) -> Predicate<TodoTask> {
        let past = Date.distantPast
        let future = Date.distantFuture
        let anyWorkspace = workspaceID == nil
        let workspace = workspaceID ?? UUID()
        return #Predicate<TodoTask> { task in
            task.deletedAt == nil && !task.isTemplate
                && (anyWorkspace || task.workspaceID == workspace)
                && (task.dueAt ?? past) >= start && (task.dueAt ?? future) < end
        }
    }

    /// Iniziate prima e in scadenza dopo la finestra (fasi lunghe).
    static func calendarSpanningPredicate(from start: Date, to end: Date, workspaceID: UUID?) -> Predicate<TodoTask> {
        let past = Date.distantPast
        let future = Date.distantFuture
        let anyWorkspace = workspaceID == nil
        let workspace = workspaceID ?? UUID()
        return #Predicate<TodoTask> { task in
            task.deletedAt == nil && !task.isTemplate
                && (anyWorkspace || task.workspaceID == workspace)
                && (task.startAt ?? future) < start && (task.dueAt ?? past) >= end
        }
    }

    /// Aperte senza date ("Da pianificare" nel calendario).
    static func unscheduledPredicate(workspaceID: UUID?) -> Predicate<TodoTask> {
        let doneRaw = TaskStatus.done.rawValue
        let anyWorkspace = workspaceID == nil
        let workspace = workspaceID ?? UUID()
        return #Predicate<TodoTask> { task in
            task.deletedAt == nil && !task.isTemplate && task.statusRaw != doneRaw
                && task.startAt == nil && task.dueAt == nil
                && (anyWorkspace || task.workspaceID == workspace)
        }
    }

    /// Esegue i predicati della finestra e ne unisce i risultati.
    static func fetchCalendarWindow(
        from start: Date, to end: Date, workspaceID: UUID?, in context: ModelContext
    ) throws -> [TodoTask] {
        let groups = try calendarWindowPredicates(from: start, to: end, workspaceID: workspaceID)
            .map { try context.fetch(FetchDescriptor(predicate: $0)) }
        return mergingUnique(groups)
    }

    /// Unisce i risultati delle query di finestra senza doppioni.
    static func mergingUnique(_ groups: [[TodoTask]]) -> [TodoTask] {
        var seen = Set<UUID>()
        return groups.joined().filter { seen.insert($0.id).inserted }
    }
}
