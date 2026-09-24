import SwiftUI
import SwiftData

/// La rubrica di produzione (D53): troupe, attrezzatura, fornitori — del
/// workspace, riusabile su TUTTI i progetti. Presentata come sheet.
struct CrewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Contact> { $0.deletedAt == nil }, sort: \Contact.name)
    private var allContacts: [Contact]

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"

    @State private var search = ""
    @State private var editing: Contact?
    @State private var isCreating = false

    private var contacts: [Contact] {
        let scoped = WorkspaceScope.filter(allContacts, raw: scopeRaw, id: \.workspaceID)
        guard !search.isEmpty else { return scoped }
        return scoped.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.role.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if contacts.isEmpty {
                    DSEmptyState(
                        icon: "person.2",
                        title: "Nessun contatto",
                        subtitle: "Troupe, attrezzatura e fornitori: li aggiungi una volta, li riusi in ogni produzione.",
                        actionTitle: "Nuovo contatto",
                        action: { isCreating = true }
                    )
                } else {
                    List {
                        ForEach(ContactKind.allCases) { kind in
                            let items = contacts.filter { $0.kind == kind }
                            if !items.isEmpty {
                                Section(kind.label) {
                                    ForEach(items, id: \.id) { contact in
                                        contactRow(contact)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Cerca per nome o ruolo")
            .navigationTitle("Troupe e risorse")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
                ToolbarItem {
                    Button {
                        isCreating = true
                    } label: {
                        Label("Nuovo contatto", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing) { contact in
                ContactEditorView(contact: contact)
            }
            .sheet(isPresented: $isCreating) {
                ContactEditorView()
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    private func contactRow(_ contact: Contact) -> some View {
        Button {
            editing = contact
        } label: {
            HStack(spacing: DS.m) {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: contact.kind.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(contact.name)
                        .font(.dsMeta.weight(.medium))
                        .foregroundStyle(.primary)
                    if !contact.role.isEmpty {
                        Text(contact.role)
                            .font(.dsCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !contact.phone.isEmpty {
                    Image(systemName: "phone")
                        .font(.dsCaption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation(.dsSoft) {
                    contact.deletedAt = .now
                    contact.updatedAt = .now
                }
            } label: {
                Label("Elimina", systemImage: "trash")
            }
        }
    }
}

/// Crea o modifica un contatto della rubrica di produzione.
struct ContactEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var contact: Contact?

    @State private var name = ""
    @State private var kind: ContactKind = .person
    @State private var role = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var notes = ""
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DSPromptField(prompt: "Nome", text: $name)
                    Picker("Tipo", selection: $kind) {
                        ForEach(ContactKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    DSPromptField(prompt: kind == .person ? "Ruolo (DOP, fonico…)" : "Categoria",
                                  text: $role)
                }
                Section("Contatti") {
                    DSPromptField(prompt: "Telefono", text: $phone)
                    DSPromptField(prompt: "Email", text: $email)
                }
                Section {
                    DSNotesEditor(text: $notes, minHeight: 60)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(contact == nil ? "Nuovo contatto" : "Modifica contatto")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(width: 380, height: 420)
        #endif
    }

    private func load() {
        guard !didLoad, let contact else { return }
        didLoad = true
        name = contact.name
        kind = contact.kind
        role = contact.role
        phone = contact.phone
        email = contact.email
        notes = contact.notes
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            if let contact {
                contact.name = trimmed
                contact.kind = kind
                contact.role = role
                contact.phone = phone
                contact.email = email
                contact.notes = notes
                contact.updatedAt = .now
            } else {
                let (workspace, _) = try SeedService.ensureSeed(in: modelContext)
                let scopeRaw = UserDefaults.standard.string(forKey: WorkspaceScope.storageKey) ?? "all"
                let workspaceID = UUID(uuidString: scopeRaw) ?? workspace.id
                let created = Contact(
                    workspaceID: workspaceID, name: trimmed, kind: kind,
                    role: role, phone: phone, email: email, notes: notes
                )
                modelContext.insert(created)
            }
            try modelContext.save()
            dismiss()
        } catch {
            reportFailure("Contact save failed: \(error)")
        }
    }
}

#Preview {
    CrewView()
        .modelContainer(PreviewSampleData.make().container)
}
