import SwiftUI
import SwiftData

/// Persone (D71) — la lente CRM: la rubrica di produzione come sezione di
/// prima classe. Chi è, che ruolo ha, su cosa sta lavorando. Lo stack lo
/// fornisce l'host (detail su Mac/iPad, push dentro Sfoglia su iPhone).
struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Contact> { $0.deletedAt == nil }, sort: \Contact.name)
    private var allContacts: [Contact]

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"

    @State private var search = ""
    @State private var isCreating = false
    @State private var showsImport = false

    private var contacts: [Contact] {
        let scoped = WorkspaceScope.filter(allContacts, raw: scopeRaw, id: \.workspaceID)
        guard !search.isEmpty else { return scoped }
        return scoped.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.role.localizedCaseInsensitiveContains(search)
                || $0.email.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Group {
            if contacts.isEmpty && search.isEmpty {
                DSEmptyState(
                    icon: "person.2",
                    title: "Nessuna persona",
                    subtitle: "Troupe, fornitori e attrezzatura: li aggiungi una volta, li riusi in ogni produzione.",
                    actionTitle: "Importa dai Contatti",
                    action: { showsImport = true }
                )
            } else {
                List {
                    ForEach(ContactKind.allCases) { kind in
                        let items = contacts.filter { $0.kind == kind }
                        if !items.isEmpty {
                            Section(kind.label) {
                                ForEach(items, id: \.id) { contact in
                                    NavigationLink {
                                        PersonDetailView(contact: contact)
                                    } label: {
                                        personRow(contact)
                                    }
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
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Cerca per nome, ruolo o email")
        .navigationTitle("Persone")
        .toolbar {
            // F40 — un solo "+": nuova persona o import, in un menu.
            ToolbarItem {
                Menu {
                    Button {
                        isCreating = true
                    } label: {
                        Label("Nuova persona", systemImage: "person.badge.plus")
                    }
                    Button {
                        showsImport = true
                    } label: {
                        Label("Importa dai Contatti…",
                              systemImage: "person.crop.circle.badge.plus")
                    }
                } label: {
                    Label("Aggiungi", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            ContactEditorView()
        }
        .sheet(isPresented: $showsImport) {
            ContactsImportView()
        }
    }

    private func personRow(_ contact: Contact) -> some View {
        HStack(spacing: DS.m) {
            if contact.kind == .person {
                AccountAvatar(name: contact.name, size: 32)
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: contact.kind.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
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
            if contact.contactIdentifier != nil {
                // Collegato ad Apple Contacts (D72).
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.dsCaption)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Collegato ai Contatti")
            }
        }
    }
}

#Preview {
    NavigationStack {
        PeopleView()
    }
    .environment(AppRouter())
    .modelContainer(PreviewSampleData.make().container)
}
