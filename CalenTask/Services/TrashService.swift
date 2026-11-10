import Foundation
import SwiftData

/// #22 — Cestino: elimina in modo definitivo le attività cancellate (soft
/// delete) da più di `retentionDays`, così DB e CloudKit non crescono per sempre.
enum TrashService {
    static let retentionDays = 30

    /// Hard delete delle task con `deletedAt` oltre la soglia. Salta quelle che
    /// hanno ancora sotto-attività vive (non si orfanano figli). Ritorna quante
    /// ne ha eliminate.
    @MainActor
    @discardableResult
    static func purgeExpired(in context: ModelContext, now: Date = .now) -> Int {
        guard let cutoff = Calendar.app.date(byAdding: .day, value: -retentionDays, to: now) else { return 0 }
        let predicate = #Predicate<TodoTask> { task in
            task.deletedAt != nil
        }
        // Il cestino è piccolo: il filtro sulla soglia avviene in memoria.
        let expired = context.fetchOrLog(FetchDescriptor<TodoTask>(predicate: predicate))
        let purgeable = expired.filter { task in
            guard let deletedAt = task.deletedAt else { return false }
            return deletedAt < cutoff && task.liveSubtasks.isEmpty
        }
        guard !purgeable.isEmpty else { return 0 }
        purgeable.forEach { context.delete($0) }
        context.saveOrLog()
        return purgeable.count
    }

    /// Attività nel cestino (radici dei sottoalberi eliminati), le più recenti prima.
    @MainActor
    static func trashedRoots(in context: ModelContext) -> [TodoTask] {
        let predicate = #Predicate<TodoTask> { $0.deletedAt != nil }
        return context.fetchOrLog(FetchDescriptor<TodoTask>(predicate: predicate))
            .filter { $0.parentTask?.deletedAt == nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    /// Ripristina una task e tutto il suo sottoalbero eliminato.
    @MainActor
    static func restore(_ task: TodoTask) {
        for child in task.subtasks where child.deletedAt != nil {
            restore(child)
        }
        guard task.deletedAt != nil else { return }
        task.deletedAt = nil
        task.touch()
    }

    /// Elimina definitivamente tutto il cestino. Ritorna quante task ha rimosso.
    @MainActor
    @discardableResult
    static func emptyTrash(in context: ModelContext) -> Int {
        let predicate = #Predicate<TodoTask> { $0.deletedAt != nil }
        let all = context.fetchOrLog(FetchDescriptor<TodoTask>(predicate: predicate))
        all.forEach { context.delete($0) }
        context.saveOrLog()
        return all.count
    }
}
