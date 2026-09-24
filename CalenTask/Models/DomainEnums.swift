import Foundation

// What a TodoTask *is*. The phase is itself a task (container with aggregated
// progress); reminders and events are tasks with a different temporal focus.
enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case task, reminder, event, phase
    /// Giorno di ripresa (S3): evento speciale che aggrega troupe,
    /// location, orari e scene — la base della call sheet.
    case shootDay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .task: "Attività"
        case .reminder: "Promemoria"
        case .event: "Evento"
        case .phase: "Fase"
        case .shootDay: "Giorno di ripresa"
        }
    }

    var systemImage: String {
        switch self {
        case .task: "checkmark.circle"
        case .reminder: "bell"
        case .event: "calendar"
        case .phase: "square.stack.3d.up"
        case .shootDay: "movieclapper"
        }
    }
}

/// Da dove arriva un task (provenienza, v8 Inbox). Lo storage "" ⇒ `.capture`
/// (i task storici sono catture rapide). CalenTaskSchemaV9.
enum TaskSource: String, Codable, CaseIterable, Identifiable {
    case capture       // cattura rapida / composer
    case request       // richiesta esterna (Intake)
    case automation    // generato da una regola di automazione
    case imported      // importato da email/calendario (futuro)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .capture: "Cattura"
        case .request: "Richiesta"
        case .automation: "Automazione"
        case .imported: "Importato"
        }
    }

    var systemImage: String {
        switch self {
        case .capture: "sparkles"
        case .request: "envelope.arrow.triangle.branch"
        case .automation: "gearshape.2"
        case .imported: "tray.and.arrow.down"
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo, doing, blocked, done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo: "Da fare"
        case .doing: "In corso"
        case .blocked: "Bloccata"
        case .done: "Completata"
        }
    }
}

enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
    case low = 0, normal, high, urgent

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .low: "Bassa"
        case .normal: "Normale"
        case .high: "Alta"
        case .urgent: "Urgente"
        }
    }
}

// MARK: Recurrence

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "Giornaliera"
        case .weekly: "Settimanale"
        case .monthly: "Mensile"
        case .yearly: "Annuale"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }
}

// Fixed: next occurrence advances from the scheduled date (calendar cadence).
// AfterCompletion: next occurrence advances from when you actually complete it (Things-style).
enum RecurrenceMode: String, Codable, CaseIterable, Identifiable {
    case fixed, afterCompletion

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: "A calendario"
        case .afterCompletion: "Dopo il completamento"
        }
    }
}

// MARK: Custom fields

enum CustomFieldType: String, Codable, CaseIterable, Identifiable {
    case text, number, date, select, checkbox, url

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: "Testo"
        case .number: "Numero"
        case .date: "Data"
        case .select: "Scelta"
        case .checkbox: "Spunta"
        case .url: "Link"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "textformat"
        case .number: "number"
        case .date: "calendar"
        case .select: "list.bullet"
        case .checkbox: "checkmark.square"
        case .url: "link"
        }
    }
}

// MARK: Saved views

enum ProjectViewType: String, Codable, CaseIterable, Identifiable {
    case summary, list, board, kanban, gantt, stripboard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .summary: "Riepilogo"
        case .list: "Elenco"
        case .board: "Bacheca"
        case .kanban: "Kanban"
        case .gantt: "Gantt"
        case .stripboard: "Scene"
        }
    }

    var systemImage: String {
        switch self {
        case .summary: "chart.pie"
        case .list: "list.bullet.indent"
        case .board: "rectangle.split.3x1"
        case .kanban: "square.grid.3x1.below.line.grid.1x2"
        case .gantt: "chart.bar.doc.horizontal"
        case .stripboard: "film.stack"
        }
    }
}

enum MembershipRole: String, Codable, CaseIterable {
    case owner, admin, member
}

enum DependencyType: String, Codable {
    case finishToStart
}

enum ProjectStatus: String, Codable, CaseIterable {
    case active, paused, completed, archived

    var label: String {
        switch self {
        case .active: "Attivo"
        case .paused: "In pausa"
        case .completed: "Completato"
        case .archived: "Archiviato"
        }
    }
}
