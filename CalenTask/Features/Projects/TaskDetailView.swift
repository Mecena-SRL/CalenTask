import SwiftUI
import SwiftData

/// Full task editor. Edits the live model (SwiftData autosaves);
/// every change goes through the mutation funnel by bumping updatedAt on disappear.
struct TaskDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var task: TodoTask

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var projects: [Project]

    @Query(filter: #Predicate<WorkflowStage> { $0.deletedAt == nil },
           sort: \WorkflowStage.order)
    private var allStages: [WorkflowStage]

    @Query(filter: #Predicate<CustomFieldDefinition> { $0.deletedAt == nil },
           sort: \CustomFieldDefinition.sortOrder)
    private var allFieldDefinitions: [CustomFieldDefinition]

    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil },
           sort: \UserProfile.createdAt)
    private var people: [UserProfile]

    @State private var newSubtaskTitle = ""

    var body: some View {
        Form {
            Section {
                TextField("", text: $task.title, prompt: Text("Titolo"), axis: .vertical)
                    .labelsHidden()
                    .font(.dsRowTitle)

                if !task.isPhase {
                    Picker("Tipo", selection: kindBinding) {
                        ForEach([TaskKind.task, .reminder, .event]) { kind in
                            Label(kind.label, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                }

                Picker("Stato", selection: statusBinding) {
                    ForEach(TaskStatus.allCases) { status in
                        Text(status.label).tag(status)
                    }
                }
                .pickerStyle(.segmented)

                DSPriorityField(priority: priorityBinding)
            }

            Section("Quando") {
                if task.kind == .event {
                    Toggle(isOn: Binding(
                        get: { task.allDay },
                        set: { task.allDay = $0; task.touch() }
                    )) {
                        DSFieldRow(label: "Tutto il giorno", systemImage: "sun.max",
                                   tint: .yellow) { EmptyView() }
                    }
                    .toggleStyle(.switch)
                    DSDateField(label: "Inizio", systemImage: "clock", tint: .blue,
                                date: dateBinding(\.startAt), includesTime: !task.allDay)
                    DSDateField(label: "Fine", systemImage: "clock.badge.checkmark", tint: .blue,
                                date: dateBinding(\.endAt), includesTime: !task.allDay)
                } else {
                    // S4 + F6: inizio e fine come ogni calendario, scadenza distinta.
                    DSDateField(label: "Inizio", systemImage: "calendar.badge.clock",
                                tint: .teal, date: dateBinding(\.startAt))
                    DSDateField(label: "Fine", systemImage: "calendar.badge.checkmark",
                                tint: .teal, date: dateBinding(\.endAt))
                    DSDateField(label: "Scadenza", systemImage: "flag", tint: .orange,
                                date: dateBinding(\.dueAt))
                }
                DSDateField(label: "Promemoria", systemImage: "bell", tint: .purple,
                            date: dateBinding(\.remindAt), includesTime: true)
            }

            // F9 — il Ripeti si modifica anche qui, con una fine.
            Section {
                DSFieldRow(
                    label: "Ripeti",
                    systemImage: "repeat",
                    tint: task.recurrenceFrequency == nil ? Color.secondary.opacity(0.55) : .teal
                ) {
                    Menu {
                        Picker("Ripeti", selection: recurrenceFrequencyBinding) {
                            Text("Mai").tag(nil as RecurrenceFrequency?)
                            ForEach(RecurrenceFrequency.allCases) { frequency in
                                Text(frequency.label).tag(frequency as RecurrenceFrequency?)
                            }
                        }
                    } label: {
                        HStack(spacing: DS.xs) {
                            Text(task.recurrenceFrequency?.label ?? "Mai")
                                .font(.dsMeta)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                if task.recurrenceFrequency != nil {
                    Picker("Logica", selection: recurrenceModeBinding) {
                        ForEach(RecurrenceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    DSDateField(label: "Fine ripetizione", systemImage: "repeat.circle",
                                tint: .teal, date: dateBinding(\.recurrenceEndAt))
                }
            }

            if task.kind == .event {
                Section("Dettagli evento") {
                    DSTextFieldRow(label: "Luogo", systemImage: "mappin.and.ellipse",
                                   tint: .red, text: Binding(
                        get: { task.locationName ?? "" },
                        set: { task.locationName = $0.isEmpty ? nil : $0; task.updatedAt = .now }
                    ))
                    // S5/D63 — tempo di viaggio → avviso "Parti ora".
                    Picker(selection: Binding(
                        get: { task.travelMinutes },
                        set: { task.travelMinutes = $0; task.touch() }
                    )) {
                        Text("Nessuno").tag(0)
                        ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    } label: {
                        DSFieldRow(label: "Tempo di viaggio", systemImage: "car",
                                   tint: .cyan) { EmptyView() }
                    }
                    DSTextFieldRow(label: "Link videochiamata", systemImage: "video",
                                   tint: .green, text: Binding(
                        get: { task.videoCallURLString ?? "" },
                        set: { task.videoCallURLString = $0.isEmpty ? nil : $0; task.updatedAt = .now }
                    ))
                }
            }

            Section("Organizzazione") {
                Picker("Progetto", selection: projectBinding) {
                    Text("Inbox (nessuno)").tag(nil as Project?)
                    // A3 (audit account): stesso spazio dell'attività, come
                    // in TaskContextMenu — un trasferimento tra spazi è
                    // un'altra azione, non ancora implementata.
                    ForEach(projects.filter { $0.workspaceID == task.workspaceID }, id: \.id) { project in
                        Text(project.name).tag(project as Project?)
                    }
                }
                // Pipeline stage (D29) — monday-style colored pill picker.
                if let project = task.project, !task.isPhase {
                    let stages = allStages.filter { $0.projectID == project.id }
                    if !stages.isEmpty {
                        Picker(selection: stageBinding(stages)) {
                            Text("Da smistare").tag(nil as UUID?)
                            ForEach(stages, id: \.id) { stage in
                                Label(stage.name, systemImage: "circle.fill")
                                    .tint(Color(hex: stage.colorHex))
                                    .tag(stage.id as UUID?)
                            }
                        } label: {
                            DSFieldRow(
                                label: "Stage pipeline",
                                systemImage: "arrow.right.square",
                                tint: currentStage(stages).map { Color(hex: $0.colorHex) }
                                    ?? Color.secondary.opacity(0.55)
                            ) { EmptyView() }
                        }
                    }
                }

                if let project = task.project, !task.isPhase, !project.phaseTasks.isEmpty,
                   task.parentTask == nil || task.parentTask?.isPhase == true {
                    Picker("Fase", selection: parentPhaseBinding) {
                        Text("Nessuna").tag(nil as TodoTask?)
                        ForEach(project.phaseTasks, id: \.id) { phase in
                            Text(phase.title).tag(phase as TodoTask?)
                        }
                    }
                }
                // Assegnazione (D34): chi se ne occupa.
                Picker(selection: Binding(
                    get: { task.assigneeID },
                    set: { task.assigneeID = $0; task.touch() }
                )) {
                    Text("Nessuno").tag(nil as UUID?)
                    ForEach(people, id: \.id) { person in
                        Text(person.name).tag(person.id as UUID?)
                    }
                } label: {
                    DSFieldRow(
                        label: "Assegnata a",
                        systemImage: "person",
                        tint: task.assigneeID == nil ? Color.secondary.opacity(0.55) : .blue
                    ) { EmptyView() }
                }

                Toggle(isOn: Binding(
                    get: { task.isClaimable },
                    set: { task.isClaimable = $0; task.updatedAt = .now }
                )) {
                    Label("Prendibile dal team", systemImage: "hand.raised")
                }
            }

            Section("Sotto-attività") {
                let subtasks = task.subtasks
                    .filter { $0.deletedAt == nil }
                    .sorted { $0.sortOrder < $1.sortOrder }
                ForEach(subtasks, id: \.id) { subtask in
                    HStack(spacing: DS.m) {
                        DSCheckToggle(isDone: subtask.isDone, font: .body) {
                            withAnimation(.dsSoft) { subtask.toggleDone() }
                        }
                        Text(subtask.title)
                            .strikethrough(subtask.isDone)
                            .foregroundStyle(subtask.isDone ? .secondary : .primary)
                        Spacer()
                        Button(role: .destructive) {
                            withAnimation { subtask.softDelete() }
                        } label: {
                            Image(systemName: "trash")
                                .font(.dsCaption)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: DS.m) {
                    Image(systemName: "plus")
                        .foregroundStyle(.tertiary)
                    TextField("", text: $newSubtaskTitle,
                              prompt: Text("Aggiungi sotto-attività"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onSubmit(addSubtask)
                    if !newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Aggiungi", action: addSubtask)
                            .buttonStyle(.borderless)
                            .font(.dsCaption)
                    }
                }
            }

            // Campi gestionali (D32): Cliente, Fattura, Margine…
            let fields = applicableFields
            if !fields.isEmpty {
                Section("Campi") {
                    ForEach(fields, id: \.id) { field in
                        CustomFieldValueRow(field: field, task: task)
                    }
                }
            }

            // Documenti e task nello stesso ambiente (D33).
            AttachmentsSection(workspaceID: task.workspaceID, taskID: task.id)

            Section {
                DSNotesEditor(text: Binding(
                    get: { task.notes },
                    set: { task.notes = $0; task.updatedAt = .now }
                ))
            }

            Section {
                Button("Elimina attività", role: .destructive) {
                    task.softDelete()
                    dismiss()
                }
            }
        }
        .formStyle(.grouped)
        // Title edits bind directly; one sync when leaving covers them.
        .onDisappear {
            TagService.syncTags(for: task, in: modelContext)
            task.touch()
        }
        .navigationTitle("Attività")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Bindings through the mutation funnel

    private var kindBinding: Binding<TaskKind> {
        Binding(get: { task.kind }, set: { task.kind = $0; task.touch() })
    }

    private var statusBinding: Binding<TaskStatus> {
        Binding(get: { task.status }, set: { task.setStatus($0) })
    }

    private var priorityBinding: Binding<TaskPriority> {
        Binding(get: { task.priority }, set: { task.priority = $0; task.touch() })
    }

    private var recurrenceFrequencyBinding: Binding<RecurrenceFrequency?> {
        Binding(
            get: { task.recurrenceFrequency },
            set: { task.recurrenceFrequency = $0; task.touch() }
        )
    }

    private var recurrenceModeBinding: Binding<RecurrenceMode> {
        Binding(
            get: { task.recurrenceMode },
            set: { task.recurrenceMode = $0; task.touch() }
        )
    }

    private func dateBinding(_ keyPath: ReferenceWritableKeyPath<TodoTask, Date?>) -> Binding<Date?> {
        Binding(
            get: { task[keyPath: keyPath] },
            set: { task[keyPath: keyPath] = $0; task.touch() }
        )
    }

    private var projectBinding: Binding<Project?> {
        Binding(
            get: { task.project },
            set: { newProject in
                task.move(to: newProject, parent: nil)
            }
        )
    }

    /// Project-scoped fields + workspace-wide ones (D32).
    private var applicableFields: [CustomFieldDefinition] {
        allFieldDefinitions.filter { field in
            if let projectID = field.projectID {
                return projectID == task.project?.id
            }
            return field.workspaceID == task.workspaceID
        }
    }

    private func currentStage(_ stages: [WorkflowStage]) -> WorkflowStage? {
        stages.first { $0.id == task.stageID }
    }

    private func stageBinding(_ stages: [WorkflowStage]) -> Binding<UUID?> {
        Binding(
            get: { task.stageID },
            set: { newID in
                task.move(toStage: stages.first { $0.id == newID })
            }
        )
    }

    /// The phase a task belongs to is just its parent of kind .phase (D5).
    private var parentPhaseBinding: Binding<TodoTask?> {
        Binding(
            get: { task.parentTask?.isPhase == true ? task.parentTask : nil },
            set: { task.parentTask = $0; task.touch() }
        )
    }

    private func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let subtask = TodoTask(
            workspaceID: task.workspaceID,
            title: title,
            sortOrder: (task.subtasks.map(\.sortOrder).max() ?? -1) + 1,
            createdByID: task.createdByID
        )
        modelContext.insert(subtask)
        subtask.parentTask = task
        subtask.project = task.project
        task.updatedAt = .now
        newSubtaskTitle = ""
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return NavigationStack {
        TaskDetailView(task: preview.tasks[0])
    }
    .modelContainer(preview.container)
}
