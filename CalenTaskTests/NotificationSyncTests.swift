import Foundation
import Testing
@testable import CalenTask

/// #19 — test sulle parti critiche: piano delle notifiche e decisioni della
/// sync EventKit che non richiedono un `EKEventStore`.
@MainActor
struct NotificationSyncTests {

    /// #4 — promemoria, scadenza e "Parti ora" hanno id e orari attesi;
    /// gli orari passati e le attività eliminate non notificano.
    @Test func remindDueAndTravelAreScheduled() throws {
        // Ora fissa a metà mattina: la scadenza non cade mai a mezzanotte (→ 9:00).
        let now = try #require(Calendar.current.date(
            bySettingHour: 10, minute: 7, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000)
        ))
        let start = now.addingTimeInterval(3 * 3600)
        let task = TodoTask(workspaceID: UUID(), title: "Sopralluogo", kind: .event,
                            startAt: start,
                            dueAt: now.addingTimeInterval(5 * 3600),
                            remindAt: now.addingTimeInterval(3600),
                            locationName: "Teatro", createdByID: UUID())
        task.travelMinutes = 30

        let schedule = NotificationService.plannedSchedule(for: task, now: now)
        let byID = Dictionary(uniqueKeysWithValues: schedule.map { ($0.id, $0.fireDate) })
        #expect(byID.count == 3)
        #expect(byID[NotificationService.remindID(task.id)] == task.remindAt)
        #expect(byID[NotificationService.dueID(task.id)] == task.dueAt)
        #expect(byID[NotificationService.travelID(task.id)] == start.addingTimeInterval(-30 * 60))

        // Promemoria già passato: resta solo il resto.
        task.remindAt = now.addingTimeInterval(-60)
        let ids = NotificationService.plannedSchedule(for: task, now: now).map { $0.id }
        #expect(!ids.contains(NotificationService.remindID(task.id)))
        #expect(ids.count == 2)

        task.deletedAt = now
        #expect(NotificationService.plannedSchedule(for: task, now: now).isEmpty)
    }

    /// #4 — il riallineamento tiene solo le richieste più vicine, ordinate,
    /// entro il limite di sistema; le completate non contano.
    @Test func resyncKeepsNearestRequestsWithinLimit() {
        let now = Date.now
        let workspace = UUID(), author = UUID()
        let tasks = (0..<70).map { index in
            TodoTask(workspaceID: workspace, title: "Task \(index)",
                     remindAt: now.addingTimeInterval(TimeInterval((70 - index) * 3600)),
                     createdByID: author)
        }
        let done = TodoTask(workspaceID: workspace, title: "Fatta", status: .done,
                            remindAt: now.addingTimeInterval(60), createdByID: author)

        let schedule = NotificationService.resyncSchedule(for: tasks + [done], now: now)
        #expect(schedule.count == NotificationService.maxPendingTaskRequests)
        #expect(zip(schedule, schedule.dropFirst()).allSatisfy { $0.fireDate <= $1.fireDate })
        // La più vicina è l'ultima creata; le 10 più lontane restano fuori.
        #expect(schedule.first?.id == NotificationService.remindID(tasks[69].id))
        let ids = Set(schedule.map { $0.id })
        #expect(!ids.contains(NotificationService.remindID(tasks[0].id)))
        #expect(!ids.contains(NotificationService.remindID(done.id)))
    }

    @Test func alertSubtitles() {
        #expect(NotificationService.alertSubtitle(minutesBefore: 0) == "Inizia ora")
        #expect(NotificationService.alertSubtitle(minutesBefore: 15) == "Tra 15 min")
        #expect(NotificationService.alertSubtitle(minutesBefore: 120) == "Tra 2 h")
        #expect(NotificationService.alertSubtitle(minutesBefore: 90) == "Tra 1 h 30 min")
        #expect(NotificationService.alertSubtitle(minutesBefore: 1440) == "Domani")
        #expect(NotificationService.alertSubtitle(minutesBefore: 2880) == "Tra 2 giorni")
    }

    /// #1, #2 — senza evento locale se ne crea uno nuovo solo quando non
    /// sarebbe un doppione di un evento di un altro dispositivo o di
    /// un'occorrenza non trovata.
    @Test func newEventOnlyWhenNotADuplicate() {
        let occurrence = EventLinkRegistry.occurrenceKey(
            series: "UID|riunione", occurrenceDate: Date(timeIntervalSince1970: 1_790_000_000)
        )
        // Mai sincronizzata: si crea.
        #expect(CalendarSyncService.mayCreateEvent(linkedKey: nil, syncedIdentifier: nil))
        // Collegata qui ma l'evento è sparito dal calendario: si ricrea.
        #expect(CalendarSyncService.mayCreateEvent(linkedKey: "EV-1", syncedIdentifier: "EV-1"))
        // Evento di un altro dispositivo non ancora arrivato: niente doppione.
        #expect(!CalendarSyncService.mayCreateEvent(linkedKey: nil, syncedIdentifier: "EV-MAC"))
        // Occorrenza di una serie non trovata: niente evento nuovo.
        #expect(!CalendarSyncService.mayCreateEvent(linkedKey: occurrence, syncedIdentifier: "EV-1"))
        #expect(!CalendarSyncService.mayCreateEvent(linkedKey: occurrence, syncedIdentifier: nil))
    }
}
