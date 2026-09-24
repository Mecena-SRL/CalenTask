import SwiftUI
import SwiftData

/// La pagina della persona (CRM-2, D71): anagrafica, azioni rapide, e il
/// lavoro VERO — convocazioni e progetti. Il CRM è una lente sul lavoro,
/// non un'altra app.
struct PersonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Bindable var contact: Contact

    @Query private var assignments: [CrewAssignment]

    @State private var isEditing = false
    @State private var refreshOutcome: RefreshOutcome?

    private enum RefreshOutcome {
        case updated, missing
    }

    init(contact: Contact) {
        self.contact = contact
        let contactID = contact.id
        _assignments = Query(filter: #Predicate<CrewAssignment> {
            $0.contactID == contactID && $0.deletedAt == nil
        })
    }

    /// Le attività convocanti (giorni di ripresa e non), vive.
    private var engagements: [TodoTask] {
        let taskIDs = assignments.map(\.taskID)
        guard !taskIDs.isEmpty else { return [] }
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate {
            taskIDs.contains($0.id) && $0.deletedAt == nil
        })
        return ((try? modelContext.fetch(descriptor)) ?? [])
            .sorted { ($0.startAt ?? $0.dueAt ?? .distantPast)
                    > ($1.startAt ?? $1.dueAt ?? .distantPast) }
    }

    private var upcoming: [TodoTask] {
        Array(engagements
            .filter { ($0.startAt ?? $0.dueAt ?? .distantPast) >= Date.now.startOfDay }
            .reversed())
    }

    private var past: [TodoTask] {
        engagements.filter { ($0.startAt ?? $0.dueAt ?? .distantPast) < Date.now.startOfDay }
    }

    private var linkedProjects: [Project] {
        var seen = Set<UUID>()
        return engagements.compactMap { task in
            guard let project = task.project, project.deletedAt == nil,
                  seen.insert(project.id).inserted else { return nil }
            return project
        }
    }

    var body: some View {
        List {
            headerSection
            actionsSection
            infoSection
            if !upcoming.isEmpty {
                engagementSection("In programma", tasks: upcoming)
            }
            if !linkedProjects.isEmpty {
                projectsSection
            }
            if !past.isEmpty {
                engagementSection("Lavori passati", tasks: Array(past.prefix(12)))
            }
            appleContactsSection
        }
        .navigationTitle(contact.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    isEditing = true
                } label: {
                    Label("Modifica", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            ContactEditorView(contact: contact)
        }
    }

    // MARK: Testata

    private var headerSection: some View {
        Section {
            HStack(spacing: DS.m) {
                if contact.kind == .person {
                    AccountAvatar(name: contact.name, size: 52)
                } else {
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: contact.kind.systemImage)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(.dsRowTitle)
                    HStack(spacing: DS.xs) {
                        if !contact.role.isEmpty {
                            Text(contact.role)
                                .font(.dsCaption)
                                .foregroundStyle(.secondary)
                        }
                        Text(contact.kind.label)
                            .font(.dsCaption.weight(.medium))
                            .padding(.horizontal, DS.s)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer()
            }
            .padding(.vertical, DS.xs)
        }
        .listRowSeparator(.hidden)
    }

    private var actionsSection: some View {
        Section {
            HStack(spacing: DS.m) {
                actionButton("Chiama", systemImage: "phone.fill",
                             enabled: !contact.phone.isEmpty) {
                    if let url = URL(string: "tel://\(sanitizedPhone)") {
                        openURL(url)
                    }
                }
                actionButton("Scrivi", systemImage: "envelope.fill",
                             enabled: !contact.email.isEmpty) {
                    if let url = URL(string: "mailto:\(contact.email)") {
                        openURL(url)
                    }
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .listRowSeparator(.hidden)
    }

    private var sanitizedPhone: String {
        contact.phone.filter { $0.isNumber || $0 == "+" }
    }

    private func actionButton(
        _ title: String, systemImage: String, enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.dsMeta.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.s)
        }
        .buttonStyle(.bordered)
        .tint(.accentColor)
        .disabled(!enabled)
    }

    // MARK: Anagrafica

    @ViewBuilder
    private var infoSection: some View {
        if !contact.phone.isEmpty || !contact.email.isEmpty || !contact.notes.isEmpty {
            Section("Contatto") {
                if !contact.phone.isEmpty {
                    LabeledContent("Telefono", value: contact.phone)
                }
                if !contact.email.isEmpty {
                    LabeledContent("Email", value: contact.email)
                }
                if !contact.notes.isEmpty {
                    Text(contact.notes)
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Lavoro

    private func engagementSection(_ title: String, tasks: [TodoTask]) -> some View {
        Section(title) {
            ForEach(tasks, id: \.id) { task in
                Button {
                    router.open(taskID: task.id)
                } label: {
                    HStack(spacing: DS.m) {
                        Image(systemName: task.kind.systemImage)
                            .font(.dsCaption)
                            .foregroundStyle(task.project.map { Color(hex: $0.colorHex) }
                                             ?? .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.title)
                                .font(.dsMeta.weight(.medium))
                                .foregroundStyle(task.isDone ? .secondary : .primary)
                                .strikethrough(task.isDone)
                                .lineLimit(1)
                            if let project = task.project {
                                Text(project.name)
                                    .font(.dsCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let date = task.startAt ?? task.dueAt {
                            Text(date.dsRelativeLabel)
                                .font(.dsCaption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var projectsSection: some View {
        Section("Progetti") {
            ForEach(linkedProjects, id: \.id) { project in
                Button {
                    router.open(projectID: project.id)
                } label: {
                    HStack(spacing: DS.s) {
                        Circle()
                            .fill(Color(hex: project.colorHex).gradient)
                            .frame(width: 10, height: 10)
                        Text(project.name)
                            .font(.dsMeta.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.dsCaption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Apple Contacts (D72)

    @ViewBuilder
    private var appleContactsSection: some View {
        if contact.contactIdentifier != nil {
            Section {
                Button {
                    let found = ContactsImportService.refresh(contact, in: modelContext)
                    withAnimation(.dsQuick) {
                        refreshOutcome = found ? .updated : .missing
                    }
                } label: {
                    Label("Aggiorna dai Contatti", systemImage: "arrow.triangle.2.circlepath")
                }
                if let refreshOutcome {
                    Text(refreshOutcome == .updated
                         ? "Telefono ed email allineati ai Contatti."
                         : "Il contatto di sistema non esiste più.")
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Collegato ad Apple Contatti: telefono ed email si riallineano da lì.")
                    .font(.dsCaption)
            }
        }
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    let contact = Contact(workspaceID: UUID(), name: "Anna Verdi",
                          role: "DOP", phone: "+39 333 1234567",
                          email: "anna@example.com")
    return NavigationStack {
        PersonDetailView(contact: contact)
    }
    .environment(AppRouter())
    .modelContainer(preview.container)
}
