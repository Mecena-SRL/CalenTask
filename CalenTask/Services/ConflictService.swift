import Foundation
import SwiftData

/// Conflitti di produzione (D55): la stessa persona o lo stesso attrezzo
/// convocati in due posti nella stessa giornata — anche su progetti e spazi
/// diversi. Il controllo è in-memory: la scala è locale, la verità è chiara.
@MainActor
enum ConflictService {
    /// Le ALTRE attività (giorni di ripresa o task) che convocano `contactID`
    /// nello stesso giorno di `day`, escludendo `taskID`.
    static func conflicts(
        contactID: UUID, day: Date, excludingTaskID taskID: UUID,
        in context: ModelContext
    ) -> [TodoTask] {
        let assignments = (try? context.fetch(FetchDescriptor<CrewAssignment>(
            predicate: #Predicate { $0.deletedAt == nil && $0.contactID == contactID }
        ))) ?? []
        let otherTaskIDs = Set(assignments.map(\.taskID)).subtracting([taskID])
        guard !otherTaskIDs.isEmpty else { return [] }

        let calendar = Calendar.current
        let tasks = (try? context.fetch(FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))) ?? []
        return tasks.filter { task in
            otherTaskIDs.contains(task.id)
                && task.startAt.map { calendar.isDate($0, inSameDayAs: day) } == true
        }
    }

    /// Tutti i contatti in conflitto per un giorno di ripresa.
    static func conflictedContactIDs(
        for shootDay: TodoTask, in context: ModelContext
    ) -> Set<UUID> {
        guard let day = shootDay.startAt else { return [] }
        let assignments = (try? context.fetch(FetchDescriptor<CrewAssignment>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))) ?? []
        let mine = assignments.filter { $0.taskID == shootDay.id }
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
