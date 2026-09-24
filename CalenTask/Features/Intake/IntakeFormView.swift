import SwiftUI
import SwiftData

/// Intake (D36): un modulo trasforma una richiesta in lavoro strutturato.
/// La task nasce prendibile dal team, taggata #richiesta, con i dati del
/// richiedente nelle note — pronta per essere censita e presa in carico.
struct IntakeFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var projects: [Project]

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    @Query(filter: #Predicate<Workspace> { $0.deletedAt == nil })
    private var workspaces: [Workspace]

    private static let requestTypes = [
        "Preventivo", "Riprese", "Montaggio", "Concerto/Evento",
        "Documentario", "Videoclip", "Altro",
    ]

    @State private var requester = ""
    @State private var contact = ""
    @State private var type = "Preventivo"
    @State private var title = ""
    @State private var details = ""
    @State private var desiredDate: Date?
    @State private var selectedProject: Project?

    var body: some View {
        NavigationStack {
            Form {
                Section("Richiedente") {
                    DSPromptField(prompt: "Nome / azienda", text: $requester)
                    DSPromptField(prompt: "Contatto (mail o telefono)", text: $contact)
                }

                Section("Richiesta") {
                    Picker("Tipo", selection: $type) {
                        ForEach(Self.requestTypes, id: \.self) { Text($0) }
                    }
                    DSPromptField(prompt: "Titolo della richiesta", text: $title)
                    DSPromptField(prompt: "Dettagli…", text: $details, vertical: true)
                        .lineLimit(3...8)
                    DSDateField(label: "Data desiderata", systemImage: "calendar",
                                tint: .orange, date: $desiredDate)
                }

                Section("Destinazione") {
                    Picker("Progetto", selection: $selectedProject) {
                        Text("Inbox richieste").tag(nil as Project?)
                        ForEach(projects, id: \.id) { project in
                            Text(project.name).tag(project as Project?)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Nuova richiesta")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea richiesta", action: submit)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                                  || requester.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }

    private func submit() {
        do {
            let (workspace, me) = try SeedService.ensureSeed(in: modelContext)
            // Le richieste vivono nello spazio società (mai in Personale): lo
            // spazio attivo se è uno spazio condiviso (A2 — è il caso comune,
            // l'Intake si apre da lì), altrimenti il primo spazio condiviso.
            let activeShared = workspaces.first { $0.id.uuidString == scopeRaw && !$0.isPersonal }
            let companyID = (activeShared ?? workspaces.first { !$0.isPersonal })?.id

            // Il richiedente ora è strutturato (V9), non più testo nelle note:
            // resta filtrabile. La nota tiene solo i dettagli liberi; il
            // tag #richiesta sopravvive per le viste/smart list storiche.
            var notes = details.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { notes += "\n\n" }
            notes += "#richiesta"

            let task = TodoTask(
                workspaceID: selectedProject?.workspaceID ?? companyID ?? workspace.id,
                title: "\(type): \(title.trimmingCharacters(in: .whitespaces))",
                notes: notes,
                dueAt: desiredDate,
                isClaimable: true,
                createdByID: me.id
            )
            modelContext.insert(task)
            task.source = .request
            task.requesterName = requester.trimmingCharacters(in: .whitespaces)
            task.requesterContact = contact.trimmingCharacters(in: .whitespaces)
            task.requestTypeLabel = type
            task.project = selectedProject
            TagService.syncTags(for: task, in: modelContext)
            try modelContext.save()
            NotificationService.shared.sync(task: task)
            dismiss()
        } catch {
            reportFailure("Intake failed: \(error)")
        }
    }
}

#Preview {
    IntakeFormView()
        .modelContainer(PreviewSampleData.make().container)
}
