import Foundation
import SwiftData

/// Punto unico di creazione delle task dal calendario (#18): spazio di
/// destinazione, identità, inserimento, salvataggio e notifiche con le stesse
/// regole ovunque.
@MainActor
enum TaskFactory {
    /// Crea una task/evento in [start, end) nello spazio di destinazione
    /// (`WorkspaceScope.creationTarget`) e la salva. Ritorna la task creata.
    @discardableResult
    static func createScheduled(
        title: String,
        kind: TaskKind,
        start: Date,
        end: Date,
        in context: ModelContext
    ) throws -> TodoTask {
        let (workspace, me) = try SeedService.identity(in: context)
        let target = WorkspaceScope.creationTarget(in: context, fallback: workspace)
        let task = TodoTask(
            workspaceID: target.id,
            title: title,
            kind: kind,
            startAt: start,
            endAt: max(end, start.addingTimeInterval(15 * 60)),
            createdByID: me.id
        )
        context.insert(task)
        try context.save()
        NotificationService.shared.sync(task: task)
        return task
    }

    /// Crea una task dentro un progetto (opzionalmente sotto una fase), con
    /// workspace e autore ereditati dal progetto. Inserisce ma non salva:
    /// il salvataggio spetta al chiamante (creazioni in blocco).
    @discardableResult
    static func createInProject(
        title: String,
        project: Project,
        phase: TodoTask? = nil,
        sortOrder: Int,
        in context: ModelContext
    ) -> TodoTask {
        let task = TodoTask(
            workspaceID: project.workspaceID,
            title: title,
            sortOrder: sortOrder,
            createdByID: project.createdByID
        )
        context.insert(task)
        task.project = project
        task.parentTask = phase
        return task
    }
}
