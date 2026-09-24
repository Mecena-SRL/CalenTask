import SwiftUI
import SwiftData

/// Automazioni del progetto (D31): lista regole + builder no-code.
/// "Quando … entra in Approvato → crea Preparare export, assegna Ivan,
/// scadenza +2 giorni, notifica Eleonora."
struct AutomationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: Project

    @Query(filter: #Predicate<AutomationRule> { $0.deletedAt == nil },
           sort: \AutomationRule.createdAt)
    private var allRules: [AutomationRule]

    @Query(filter: #Predicate<WorkflowStage> { $0.deletedAt == nil },
           sort: \WorkflowStage.order)
    private var allStages: [WorkflowStage]

    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil },
           sort: \UserProfile.createdAt)
    private var people: [UserProfile]

    @State private var editingRule: AutomationRule?

    private var rules: [AutomationRule] {
        allRules.filter { $0.projectID == project.id }
    }

    private var stages: [WorkflowStage] {
        allStages.filter { $0.projectID == project.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if rules.isEmpty {
                    DSEmptyState(
                        icon: "bolt.badge.automatic",
                        title: "Nessuna automazione",
                        subtitle: "Esempio: quando una task entra in \"Approvato\", crea \"Preparare export\", assegnala e notifica il team. Una regola, zero lavoro ripetitivo.",
                        actionTitle: "Nuova regola",
                        action: addRule
                    )
                } else {
                    List {
                        ForEach(rules, id: \.id) { rule in
                            Button {
                                editingRule = rule
                            } label: {
                                ruleRow(rule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Automazioni · \(project.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: addRule) {
                        Label("Nuova regola", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editingRule) { rule in
                AutomationRuleEditor(rule: rule, stages: stages, people: people)
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 440)
        #endif
    }

    private func ruleRow(_ rule: AutomationRule) -> some View {
        HStack(spacing: DS.m) {
            DSIconTile(
                systemImage: "bolt.fill",
                tint: rule.isEnabled ? .yellow : Color.secondary.opacity(0.5)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.dsMeta.weight(.medium))
                Text(summary(for: rule))
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { rule.isEnabled = $0; rule.updatedAt = .now }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            Button(role: .destructive) {
                withAnimation { rule.deletedAt = .now; rule.updatedAt = .now }
            } label: {
                Image(systemName: "trash")
                    .font(.dsCaption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }

    private func summary(for rule: AutomationRule) -> String {
        var when: String
        switch rule.triggerType {
        case .enteredStage:
            let stage = stages.first { $0.id == rule.triggerStageID }?.name ?? "uno stage"
            when = "Quando entra in «\(stage)»"
        case .statusChanged:
            when = "Quando passa a «\(rule.triggerStatus?.label ?? "stato")»"
        }
        var actions: [String] = []
        if let title = rule.createTaskTitle, !title.isEmpty {
            actions.append("crea «\(title)»")
            if let offset = rule.createTaskDueOffsetDays { actions.append("scadenza +\(offset)g") }
            if let assignee = rule.createTaskAssigneeID {
                actions.append("assegna \(name(of: assignee))")
            }
        }
        if let assignee = rule.assignToID { actions.append("riassegna a \(name(of: assignee))") }
        if let notify = rule.notifyUserID { actions.append("notifica \(name(of: notify))") }
        return when + " → " + (actions.isEmpty ? "nessuna azione" : actions.joined(separator: ", "))
    }

    private func name(of id: UUID) -> String {
        people.first { $0.id == id }?.name ?? "?"
    }

    private func addRule() {
        let rule = AutomationRule(
            workspaceID: project.workspaceID,
            projectID: project.id,
            name: "Nuova regola",
            triggerType: stages.isEmpty ? .statusChanged : .enteredStage
        )
        if stages.isEmpty {
            rule.triggerStatus = .done
        } else {
            rule.triggerStageID = stages.first?.id
        }
        modelContext.insert(rule)
        editingRule = rule
    }
}

// MARK: - Editor

private struct AutomationRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var rule: AutomationRule
    let stages: [WorkflowStage]
    let people: [UserProfile]

    @State private var createsTask = false
    @State private var dueOffsetEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DSPromptField(prompt: "Nome regola", text: Binding(
                        get: { rule.name },
                        set: { rule.name = $0; rule.updatedAt = .now }
                    ))
                    .font(.dsRowTitle)
                }

                Section("Quando") {
                    Picker("Trigger", selection: Binding(
                        get: { rule.triggerType },
                        set: { rule.triggerType = $0; rule.updatedAt = .now }
                    )) {
                        if !stages.isEmpty {
                            Text(AutomationRule.TriggerType.enteredStage.label)
                                .tag(AutomationRule.TriggerType.enteredStage)
                        }
                        Text(AutomationRule.TriggerType.statusChanged.label)
                            .tag(AutomationRule.TriggerType.statusChanged)
                    }
                    .pickerStyle(.segmented)

                    if rule.triggerType == .enteredStage {
                        Picker("Stage", selection: Binding(
                            get: { rule.triggerStageID },
                            set: { rule.triggerStageID = $0; rule.updatedAt = .now }
                        )) {
                            ForEach(stages, id: \.id) { stage in
                                Label(stage.name, systemImage: "circle.fill")
                                    .tint(Color(hex: stage.colorHex))
                                    .tag(stage.id as UUID?)
                            }
                        }
                    } else {
                        Picker("Stato", selection: Binding(
                            get: { rule.triggerStatus ?? .done },
                            set: { rule.triggerStatus = $0; rule.updatedAt = .now }
                        )) {
                            ForEach(TaskStatus.allCases) { status in
                                Text(status.label).tag(status)
                            }
                        }
                    }
                }

                Section("Allora") {
                    Toggle("Crea un'attività", isOn: $createsTask.animation(.dsQuick))
                    if createsTask {
                        DSPromptField(prompt: "Titolo ({task} = titolo origine)", text: Binding(
                            get: { rule.createTaskTitle ?? "" },
                            set: { rule.createTaskTitle = $0.isEmpty ? nil : $0
                                   rule.updatedAt = .now }
                        ))
                        personPicker("Assegnala a", selection: Binding(
                            get: { rule.createTaskAssigneeID },
                            set: { rule.createTaskAssigneeID = $0; rule.updatedAt = .now }
                        ))
                        Toggle("Con scadenza", isOn: $dueOffsetEnabled.animation(.dsQuick))
                        if dueOffsetEnabled {
                            Stepper(
                                "Scadenza: +\(rule.createTaskDueOffsetDays ?? 2) giorni",
                                value: Binding(
                                    get: { rule.createTaskDueOffsetDays ?? 2 },
                                    set: { rule.createTaskDueOffsetDays = $0; rule.updatedAt = .now }
                                ),
                                in: 0...60
                            )
                        }
                    }

                    personPicker("Riassegna l'attività a", selection: Binding(
                        get: { rule.assignToID },
                        set: { rule.assignToID = $0; rule.updatedAt = .now }
                    ))

                    personPicker("Notifica", selection: Binding(
                        get: { rule.notifyUserID },
                        set: { rule.notifyUserID = $0; rule.updatedAt = .now }
                    ))
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Regola")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .onAppear {
                createsTask = rule.createTaskTitle != nil
                dueOffsetEnabled = rule.createTaskDueOffsetDays != nil
            }
            .onChange(of: createsTask) { _, enabled in
                if !enabled {
                    rule.createTaskTitle = nil
                    rule.createTaskAssigneeID = nil
                    rule.createTaskDueOffsetDays = nil
                }
            }
            .onChange(of: dueOffsetEnabled) { _, enabled in
                rule.createTaskDueOffsetDays = enabled ? (rule.createTaskDueOffsetDays ?? 2) : nil
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 480)
        #endif
    }

    private func personPicker(_ label: String, selection: Binding<UUID?>) -> some View {
        Picker(label, selection: selection) {
            Text("Nessuno").tag(nil as UUID?)
            ForEach(people, id: \.id) { person in
                Text(person.name).tag(person.id as UUID?)
            }
        }
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return AutomationListView(project: preview.project)
        .modelContainer(preview.container)
}
