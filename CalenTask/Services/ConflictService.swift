import Foundation
import SwiftData

/// Conflitti di produzione (D55): la stessa persona o lo stesso attrezzo
/// convocati in due posti nella stessa giornata — anche su progetti e spazi
/// diversi. Assegnazioni e attività del giorno sono filtrate nello store.
@MainActor
enum ConflictService {
    /// Le ALTRE attività (giorni di ripresa o task) che convocano `contactID`
    /// nello stesso giorno di `day`, escludendo `taskID`.
    static func conflicts(
        contactID: UUID, day: Date, excludingTaskID taskID: UUID,
        in context: ModelContext
    ) -> [TodoTask] {
        let assignments = context.fetchOrLog(FetchDescriptor<CrewAssignment>(
            predicate: #Predicate { $0.deletedAt == nil && $0.contactID == contactID }
        ))
        let otherTaskIDs = Array(Set(assignments.map(\.taskID)).subtracting([taskID]))
        guard !otherTaskIDs.isEmpty else { return [] }

        // #5 — solo quelle attività e solo in quel giorno, filtrate nello store.
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let past = Date.distantPast
        let future = Date.distantFuture
        return context.fetchOrLog(FetchDescriptor<TodoTask>(predicate: #Predicate { task in
            otherTaskIDs.contains(task.id) && task.deletedAt == nil
                && (task.startAt ?? past) >= dayStart && (task.startAt ?? future) < dayEnd
        }))
    }

    /// Tutti i contatti in conflitto per un giorno di ripresa.
    static func conflictedContactIDs(
        for shootDay: TodoTask, in context: ModelContext
    ) -> Set<UUID> {
        guard let day = shootDay.startAt else { return [] }
        let shootDayID = shootDay.id
        let mine = context.fetchOrLog(FetchDescriptor<CrewAssignment>(
            predicate: #Predicate { $0.deletedAt == nil && $0.taskID == shootDayID }
        ))
        var conflicted: Set<UUID> = []
        for assignment in mine where !conflicts(
            contactID: assignment.contactID, day: day,
            excludingTaskID: shootDay.id, in: context
        ).isEmpty {
            conflicted.insert(assignment.contactID)
        }
        return conflicted
    }
}
