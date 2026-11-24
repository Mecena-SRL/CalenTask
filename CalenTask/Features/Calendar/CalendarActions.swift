import Foundation
import SwiftData

/// Le azioni del calendario condivise da Giorno, Settimana e Mese (prima
/// copiate in ogni vista): ri-datare un'attività trascinata su un altro
/// giorno e creare un'attività aprendo subito l'editor.
@MainActor
enum CalendarActions {
    /// Sposta un'attività sul `day` di destinazione preservando l'ora: lo
    /// scarto in giorni dall'ancora (inizio, o la scadenza) trasla inizio,
    /// fine e scadenza. Il funnel `touch()` riallinea notifiche ed EventKit.
    @discardableResult
    static func reschedule(taskID idString: String, to day: Date,
                           in context: ModelContext, calendar: Calendar) -> Bool {
        guard let id = UUID(uuidString: idString),
              let task = context.fetchOrLog(
                FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })
              ).first,
              let anchor = task.startAt ?? task.dueAt
        else { return false }

        let deltaDays = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: anchor), to: calendar.startOfDay(for: day)
        ).day ?? 0
        guard deltaDays != 0 else { return false }

        if let start = task.startAt {
            task.startAt = calendar.date(byAdding: .day, value: deltaDays, to: start)
        }
        if let end = task.endAt {
            task.endAt = calendar.date(byAdding: .day, value: deltaDays, to: end)
        }
        if let due = task.dueAt {
            task.dueAt = calendar.date(byAdding: .day, value: deltaDays, to: due)
        }
        task.touch()
        return true
    }

    /// Crea "Nuova attività" in [start, end) nello spazio di destinazione e
    /// apre l'editor (i dettagli si mettono lì).
    static func createTask(start: Date, end: Date, in context: ModelContext, router: AppRouter) {
        do {
            let task = try TaskFactory.createScheduled(
                title: "Nuova attività", kind: .task, start: start, end: end, in: context)
            #if os(macOS)
            router.inspect(taskID: task.id)
            #else
            router.open(taskID: task.id)
            #endif
        } catch {
            reportFailure("create calendar task: \(error)")
        }
    }
}
