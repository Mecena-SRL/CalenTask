import SwiftUI
import SwiftData

/// Gestione persone (D34): il team con cui lavorano automazioni,
/// assegnazioni, workload e dashboard per ruolo.
struct TeamView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil },
           sort: \UserProfile.createdAt)
    private var people: [UserProfile]

    @Query(filter: TodoTask.openPredicate)
    private var openTasks: [TodoTask]

    @State private var newName = ""
    @State private var newEmail = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(people, id: \.id) { person in
                    HStack(spacing: DS.m) {
                        avatar(for: person)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.name)
                                .font(.dsMeta.weight(.medium))
                            if !person.email.isEmpty {
                                Text(person.email)
                                    .font(.dsCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        let load = openTasks.filter { $0.assigneeID == person.id }.count
                        if load > 0 {
                            Text("\(load) attività")
                                .font(.dsNumeric)
                                .foregroundStyle(.secondary)
                        }
                        if people.count > 1 {
                            Button(role: .destructive) {
                                withAnimation { person.deletedAt = .now; person.updatedAt = .now }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.dsCaption)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Nuova persona") {
                    TextField("Nome", text: $newName)
                    TextField("Email (facoltativa)", text: $newEmail)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    Button("Aggiungi al team", action: addPerson)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Team")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    private func avatar(for person: UserProfile) -> some View {
        let initials = person.name.split(separator: " ").prefix(2)
            .compactMap(\.first).map(String.init).joined()
        return Text(initials.isEmpty ? "?" : initials)
            .font(.dsCaption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Color(hex: avatarColor(for: person)).gradient, in: Circle())
    }

    private func avatarColor(for person: UserProfile) -> String {
        TagService.defaultPalette[abs(person.id.hashValue) % TagService.defaultPalette.count]
    }

    private func addPerson() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        modelContext.insert(UserProfile(
            name: name, email: newEmail.trimmingCharacters(in: .whitespaces)
        ))
        newName = ""
        newEmail = ""
    }
}

#Preview {
    TeamView()
        .modelContainer(PreviewSampleData.make().container)
}
