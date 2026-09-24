import Foundation
import SwiftData

// The unified core entity: todo + calendar event + reminder + phase container.
// Named TodoTask because `Task` collides with _Concurrency.Task.
// Maps to future Supabase table `tasks`.
@Model
final class TodoTask {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var kindRaw: String = ""
    var statusRaw: String = ""
    var priorityRaw: Int = 0

    // Temporal facets: event (startAt/endAt), deadline (dueAt), reminder (remindAt).
    var startAt: Date?
    var endAt: Date?
    var dueAt: Date?
    var remindAt: Date?

    // Deep event fields (mapped to/from EventKit where possible).
    var allDay: Bool = false
    var timeZoneID: String?
    var locationName: String?
    var videoCallURLString: String?
    var attendees: [String] = []
    /// Minutes before the reference date (startAt for events, dueAt otherwise).
    /// Multiple alerts per item; 0 = at time of event.
    var alertOffsetsMinutes: [Int] = []
    /// EventKit round-trip identifiers (nil ⇒ never synced to the system calendar).
    var eventIdentifier: String?
    var calendarIdentifier: String?

    // Recurrence: present when frequencyRaw != nil.
    var recurrenceFrequencyRaw: String?
    var recurrenceInterval: Int = 0
    var recurrenceModeRaw: String?
    var recurrenceEndAt: Date?
    /// #8 — Ancora della serie: la data (scadenza, o inizio) della prima
    /// occorrenza. Tiene il giorno del mese: 31/01 → 28/02 → 31/03, non
    /// 28/03. nil ⇒ la serie non ha ancora generato occorrenze.
    /// CalenTaskSchemaV11.
    var recurrenceAnchorAt: Date?

    /// Template tasks/phases are blueprints: excluded from every operational
    /// list, instantiated on demand (D13).
    var isTemplate: Bool = false

    /// Colore proprio (oggi usato dalle FASI in Bacheca, D57); vuoto ⇒ il
    /// colore del progetto. Aggiunto in CalenTaskSchemaV3.
    var colorHex: String = ""

    /// Tempo di viaggio in minuti per gli eventi con luogo (S5/D63):
    /// genera l'avviso "Parti ora" prima dell'inizio. CalenTaskSchemaV4.
    var travelMinutes: Int = 0

    /// Pipeline stage within the project's custom workflow (D29).
    var stageID: UUID?

    // Collaboration: assignment, delegation, self-assign board.
    var assigneeID: UUID?
    var delegatedByID: UUID?
    var isClaimable: Bool = false

    /// Provenienza del task (v8 Inbox): come è entrato nel sistema. Storage ""
    /// ⇒ `.capture`. CalenTaskSchemaV9.
    var sourceRaw: String = ""

    /// Dati strutturati del richiedente per le richieste esterne (Intake):
    /// prima erano testo libero nelle note, ora filtrabili. CalenTaskSchemaV9.
    var requesterName: String = ""
    var requesterContact: String = ""
    var requestTypeLabel: String = ""

    var sortOrder: Int = 0
    var createdByID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    /// V7 — quando è stata completata (per l'andamento in dashboard, F15).
    var completedAt: Date?

    var project: Project?   // nil ⇒ Inbox
    var parentTask: TodoTask?

    // CloudKit esige relazioni OPZIONALI (v7-fix): lo storage è optional con
    // `originalName` (i dati locali migrano da soli), l'API resta non-optional
    // via bridge calcolato — stesso pattern di statusRaw/status.
    @Relationship(deleteRule: .cascade, originalName: "subtasks",
                  inverse: \TodoTask.parentTask)
    var subtasksStorage: [TodoTask]? = []

    @Relationship(originalName: "tags", inverse: \Tag.tasksStorage)
    var tagsStorage: [Tag]? = []

    var subtasks: [TodoTask] {
        get { subtasksStorage ?? [] }
        set { subtasksStorage = newValue }
    }

    var tags: [Tag] {
        get { tagsStorage ?? [] }
        set { tagsStorage = newValue }
    }

    var kind: TaskKind {
        get { TaskKind(rawValue: kindRaw) ?? .task }
        set { kindRaw = newValue.rawValue }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var source: TaskSource {
        get { TaskSource(rawValue: sourceRaw) ?? .capture }
        set { sourceRaw = newValue.rawValue }
    }

    /// Una richiesta esterna: dal campo strutturato o (per i dati pre-v8) dal
    /// tag/nota `#richiesta` lasciato dall'Intake storico.
    var isExternalRequest: Bool {
        source == .request
            || notes.localizedCaseInsensitiveContains("#richiesta")
            || tags.contains { $0.name.localizedCaseInsensitiveCompare("richiesta") == .orderedSame }
    }

    var recurrenceFrequency: RecurrenceFrequency? {
        get { recurrenceFrequencyRaw.flatMap(RecurrenceFrequency.init(rawValue:)) }
        set { recurrenceFrequencyRaw = newValue?.rawValue }
    }

    var recurrenceMode: RecurrenceMode {
        get { recurrenceModeRaw.flatMap(RecurrenceMode.init(rawValue:)) ?? .fixed }
        set { recurrenceModeRaw = newValue.rawValue }
    }

    var hasRecurrence: Bool { recurrenceFrequencyRaw != nil }

    var videoCallURL: URL? {
        get { videoCallURLString.flatMap(URL.init(string:)) }
        set { videoCallURLString = newValue?.absoluteString }
    }

    var isDone: Bool { statusRaw == TaskStatus.done.rawValue }

    var isPhase: Bool { kindRaw == TaskKind.phase.rawValue }

    var isOverdue: Bool {
        guard let dueAt, !isDone else { return false }
        return dueAt < Calendar.current.startOfDay(for: .now)
    }

    /// Live (non-deleted) children, ordered.
    var liveSubtasks: [TodoTask] {
        subtasks
            .filter { $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Nearest ancestor of kind .phase (the "phase" this task belongs to), if any.
    var phaseAncestor: TodoTask? {
        var node = parentTask
        while let current = node {
            if current.isPhase { return current }
            node = current.parentTask
        }
        return nil
    }

    /// Aggregated progress of the subtree (leaf tasks only), for phase containers.
    var aggregatedProgress: Double {
        let leaves = descendantLeaves
        guard !leaves.isEmpty else { return isDone ? 1 : 0 }
        return Double(leaves.filter(\.isDone).count) / Double(leaves.count)
    }

    private var descendantLeaves: [TodoTask] {
        let children = liveSubtasks
        guard !children.isEmpty else { return [] }
        return children.flatMap { child -> [TodoTask] in
            let nested = child.descendantLeaves
            return nested.isEmpty ? [child] : nested
        }
    }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        title: String,
        notes: String = "",
        kind: TaskKind = .task,
        status: TaskStatus = .todo,
        priority: TaskPriority = .normal,
        startAt: Date? = nil,
        endAt: Date? = nil,
        dueAt: Date? = nil,
        remindAt: Date? = nil,
        allDay: Bool = false,
        timeZoneID: String? = nil,
        locationName: String? = nil,
        videoCallURLString: String? = nil,
        attendees: [String] = [],
        alertOffsetsMinutes: [Int] = [],
        isTemplate: Bool = false,
        assigneeID: UUID? = nil,
        delegatedByID: UUID? = nil,
        isClaimable: Bool = false,
        sortOrder: Int = 0,
        createdByID: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.title = title
        self.notes = notes
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.startAt = startAt
        self.endAt = endAt
        self.dueAt = dueAt
        self.remindAt = remindAt
        self.allDay = allDay
        self.timeZoneID = timeZoneID
        self.locationName = locationName
        self.videoCallURLString = videoCallURLString
        self.attendees = attendees
        self.alertOffsetsMinutes = alertOffsetsMinutes
        self.recurrenceInterval = 1
        self.isTemplate = isTemplate
        self.assigneeID = assigneeID
        self.delegatedByID = delegatedByID
        self.isClaimable = isClaimable
        self.sortOrder = sortOrder
        self.createdByID = createdByID
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.subtasksStorage = []
        self.tagsStorage = []
    }
}
