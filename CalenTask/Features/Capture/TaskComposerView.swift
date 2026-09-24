import SwiftUI
import SwiftData

/// The full composer (D9): type, adaptive dates, project/phase, priority,
/// recurrence, inline subtasks, notes. Creation only — editing lives in
/// TaskDetailView. This is the app's showcase: every field is a DS field row.
struct TaskComposerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Pre-fill from quick capture ("espandi") or from a calendar day tap.
    var initialTitle: String = ""
    var initialDueDate: Date? = nil
    var initialKind: TaskKind = .task

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var projects: [Project]

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    @Query(filter: #Predicate<Workspace> { $0.deletedAt == nil })
    private var workspaces: [Workspace]

    @State private var title = ""
    @State private var notes = ""
    @State private var kind: TaskKind = .task
    @State private var priority: TaskPriority = .normal

    @State private var dueAt: Date?
    @State private var remindAt: Date?
    @State private var startAt: Date?
    @State private var endAt: Date?
    @State private var allDay = false
    @State private var locationName = ""
    @State private var videoCallURLString = ""

    @State private var recurrenceFrequency: RecurrenceFrequency?
    @State private var recurrenceMode: RecurrenceMode = .fixed
    @State private var recurrenceEndAt: Date?

    @State private var selectedProject: Project?
    @State private var selectedPhaseID: UUID?
    @State private var subtaskTitles: [String] = []
    @State private var newSubtaskTitle = ""

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                kindSection
                datesSection
                if kind == .event { eventDetailsSection }
                recurrenceSection
                organizationSection
                subtasksSection
                notesSection
            }
            .formStyle(.grouped)
            .navigationTitle("Nuova \(kind == .event ? "evento" : kind.label.lowercased())")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea", action: save)
                        .disabled(trimmedTitle.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .onAppear {
                title = initialTitle
                dueAt = initialDueDate
                kind = initialKind
                isTitleFocused = true
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    // MARK: Sections

    private var titleSection: some View {
        Section {
            TextField("", text: $title, prompt: Text(titlePlaceholder), axis: .vertical)
                .labelsHidden()
                .font(.dsRowTitle)
                .focused($isTitleFocused)
        }
    }

    private var kindSection: some View {
        Section {
            Picker("Tipo", selection: $kind.animation(.dsQuick)) {
                ForEach([TaskKind.task, .reminder, .event]) { kind in
                    Label(kind.label, systemImage: kind.systemImage).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var datesSection: some View {
        Section("Quando") {
            switch kind {
            case .task, .phase, .shootDay:
                // S4 + F6: inizio e fine come ogni calendario, scadenza distinta.
                DSDateField(label: "Inizio", systemImage: "calendar.badge.clock",
                            tint: .teal, date: $startAt)
                DSDateField(label: "Fine", systemImage: "calendar.badge.checkmark",
                            tint: .teal, date: $endAt)
                DSDateField(label: "Scadenza", systemImage: "flag",
                            tint: .orange, date: $dueAt)
                DSDateField(label: "Promemoria", systemImage: "bell",
                            tint: .purple, date: $remindAt, includesTime: true)
            case .reminder:
                DSDateField(label: "Promemoria", systemImage: "bell",
                            tint: .purple, date: $remindAt, includesTime: true)
            case .event:
                Toggle(isOn: $allDay.animation(.dsQuick)) {
                    DSFieldRow(label: "Tutto il giorno", systemImage: "sun.max",
                               tint: .yellow) { EmptyView() }
                }
                .toggleStyle(.switch)
                DSDateField(label: "Inizio", systemImage: "clock",
                            tint: .blue, date: $startAt, includesTime: !allDay)
                DSDateField(label: "Fine", systemImage: "clock.badge.checkmark",
                            tint: .blue, date: $endAt, includesTime: !allDay)
                DSDateField(label: "Promemoria", systemImage: "bell",
                            tint: .purple, date: $remindAt, includesTime: true)
            }
        }
    }

    private var eventDetailsSection: some View {
        Section("Dettagli evento") {
            DSTextFieldRow(label: "Luogo", systemImage: "mappin.and.ellipse",
                           tint: .red, text: $locationName)
            DSTextFieldRow(label: "Link videochiamata", systemImage: "video",
                           tint: .green, text: $videoCallURLString)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
        }
    }

    private var recurrenceSection: some View {
        Section {
            DSFieldRow(
                label: "Ripeti",
                systemImage: "repeat",
                tint: recurrenceFrequency == nil ? Color.secondary.opacity(0.55) : .teal
            ) {
                Menu {
                    Picker("Ripeti", selection: $recurrenceFrequency.animation(.dsQuick)) {
                        Text("Mai").tag(nil as RecurrenceFrequency?)
                        ForEach(RecurrenceFrequency.allCases) { frequency in
                            Text(frequency.label).tag(frequency as RecurrenceFrequency?)
                        }
                    }
                } label: {
                    HStack(spacing: DS.xs) {
                        Text(recurrenceFrequency?.label ?? "Mai")
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

            if recurrenceFrequency != nil {
                Picker("Logica", selection: $recurrenceMode) {
                    ForEach(RecurrenceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                // F9 — la ripetizione può finire.
                DSDateField(label: "Fine ripetizione", systemImage: "repeat.circle",
                            tint: .teal, date: $recurrenceEndAt)
            }
        }
    }

    @ViewBuilder
    private var organizationSection: some View {
        Section("Organizzazione") {
            Picker(selection: $selectedProject.animation(.dsQuick)) {
                Text("Inbox (nessuno)").tag(nil as Project?)
                ForEach(projects, id: \.id) { project in
                    Text(project.name).tag(project as Project?)
                }
            } label: {
                DSFieldRow(label: "Progetto", systemImage: "folder",
                           tint: selectedProject.map { Color(hex: $0.colorHex) } ?? Color.secondary.opacity(0.55)) {
                    EmptyView()
                }
            }

            if let project = selectedProject, !project.phaseTasks.isEmpty {
                Picker(selection: $selectedPhaseID) {
                    Text("Nessuna").tag(nil as UUID?)
                    ForEach(project.phaseTasks, id: \.id) { phase in
                        Text(phase.title).tag(phase.id as UUID?)
                    }
                } label: {
                    DSFieldRow(label: "Fase", systemImage: "square.stack.3d.up",
                               tint: Color(hex: project.colorHex)) { EmptyView() }
                }
            }

            DSPriorityField(priority: $priority)
        }
    }

    private var subtasksSection: some View {
        Section("Sotto-attività") {
            ForEach(Array(subtaskTitles.enumerated()), id: \.offset) { index, subtask in
                HStack(spacing: DS.m) {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                    Text(subtask)
                    Spacer()
                    Button {
                        subtaskTitles.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
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
    }

    private var notesSection: some View {
        Section {
            DSNotesEditor(text: $notes)
        }
    }

    // MARK: Actions

    private var titlePlaceholder: String {
        switch kind {
        case .task, .phase: "Cosa c'è da fare?"
        case .reminder: "Cosa devo ricordarti?"
        case .event: "Titolo dell'evento"
        case .shootDay: "Titolo del giorno di ripresa"
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addSubtask() {
        let text = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        subtaskTitles.append(text)
        newSubtaskTitle = ""
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        do {
            let (workspace, me) = try SeedService.ensureSeed(in: modelContext)
            let target = WorkspaceScope.creationTarget(raw: scopeRaw, workspaces: workspaces) ?? workspace
            let task = TodoTask(
                workspaceID: selectedProject?.workspaceID ?? target.id,
                title: trimmedTitle,
                notes: notes,
                kind: kind,
                priority: priority,
                startAt: kind == .reminder ? nil : startAt,
                endAt: kind == .reminder ? nil : endAt,
                dueAt: kind == .event ? nil : dueAt,
                remindAt: remindAt,
                allDay: kind == .event && allDay,
                locationName: locationName.isEmpty ? nil : locationName,
                videoCallURLString: videoCallURLString.isEmpty ? nil : videoCallURLString,
                createdByID: me.id
            )
            if let frequency = recurrenceFrequency {
                task.recurrenceFrequency = frequency
                task.recurrenceMode = recurrenceMode
                task.recurrenceEndAt = recurrenceEndAt
            }
            modelContext.insert(task)
            task.project = selectedProject
            task.parentTask = selectedProject?.phaseTasks.first { $0.id == selectedPhaseID }

            for (index, subtaskTitle) in subtaskTitles.enumerated() {
                let subtask = TodoTask(
                    workspaceID: task.workspaceID,
                    title: subtaskTitle,
                    sortOrder: index,
                    createdByID: me.id
                )
                modelContext.insert(subtask)
                subtask.parentTask = task
                subtask.project = selectedProject
            }

            TagService.syncTags(for: task, in: modelContext)
            try modelContext.save()
            NotificationService.shared.sync(task: task)
            dismiss()
        } catch {
            assertionFailure("Composer save failed: \(error)")
        }
    }
}

#Preview {
    TaskComposerView()
        .modelContainer(PreviewSampleData.make().container)
}
