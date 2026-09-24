import Foundation

/// #5 — I contatori delle viste sempre montate (badge della sidebar,
/// progetti, mini-mese, selettore spazi) in UN passaggio sulle attività
/// aperte già caricate, invece di un passaggio per ogni badge a ogni render.
struct OpenTaskStats {
    private(set) var total = 0
    private(set) var byProject: [UUID: Int] = [:]
    /// Con inizio, scadenza o promemoria oggi.
    private(set) var today = 0
    /// Eventi che iniziano oggi.
    private(set) var todayEvents = 0
    /// Giornate con attività (inizio o scadenza) → pallini del mini-mese.
    private(set) var byDay: [Date: Int] = [:]

    init(tasks: [TodoTask], calendar: Calendar, now: Date = .now) {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        func isToday(_ date: Date?) -> Bool {
            guard let date else { return false }
            return date >= todayStart && date < tomorrowStart
        }
        for task in tasks {
            total += 1
            if let projectID = task.project?.id { byProject[projectID, default: 0] += 1 }
            let start = task.startAt
            let due = task.dueAt
            if isToday(start) || isToday(due) || isToday(task.remindAt) { today += 1 }
            if task.kind == .event, isToday(start) { todayEvents += 1 }
            if let start { byDay[calendar.startOfDay(for: start), default: 0] += 1 }
            if let due { byDay[calendar.startOfDay(for: due), default: 0] += 1 }
        }
    }
}
