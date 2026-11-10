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

    /// Elimina subito e per sempre le task indicate (svuota cestino).
    @MainActor
    static func deleteForever(_ tasks: [TodoTask], in context: ModelContext) {
        guard !tasks.isEmpty else { return }
        tasks.forEach { context.delete($0) }
        context.saveOrLog()
    }
}
