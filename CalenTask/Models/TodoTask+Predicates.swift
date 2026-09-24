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

    /// Task con un inizio che tocca [start, end): eventi anche su più giorni
    /// e fasi (inizio → scadenza) che attraversano la finestra.
    static func calendarStartPredicate(from start: Date, to end: Date, workspaceID: UUID?) -> Predicate<TodoTask> {
        let past = Date.distantPast
        let future = Date.distantFuture
        let anyWorkspace = workspaceID == nil
        let workspace = workspaceID ?? UUID()
        return #Predicate<TodoTask> { task in
            task.deletedAt == nil && !task.isTemplate
                && (anyWorkspace || task.workspaceID == workspace)
                && (task.startAt ?? future) < end
                && (task.endAt ?? task.dueAt ?? task.startAt ?? past) >= start
        }
    }

    /// Task con scadenza in [start, end).
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

    /// Unisce i risultati delle query di finestra senza doppioni.
    static func mergingUnique(_ groups: [TodoTask]...) -> [TodoTask] {
        var seen = Set<UUID>()
        return groups.joined().filter { seen.insert($0.id).inserted }
    }
}
