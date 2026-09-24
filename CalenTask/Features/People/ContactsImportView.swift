import SwiftUI
import SwiftData

/// "Importa dai Contatti" (CRM-1, D72): selezione multipla dalla rubrica del
/// device, dedupe automatico per identifier/email, atterraggio nello spazio
/// attivo. Funziona uguale su Mac, iPad e iPhone.
struct ContactsImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Contact> { $0.deletedAt == nil })
    private var existingContacts: [Contact]

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"

    @State private var phase: Phase = .loading
    @State private var deviceContacts: [ContactsImportService.DeviceContact] = []
    @State private var selection = Set<String>()
    @State private var search = ""

    private enum Phase {
        case loading, denied, ready
    }

    /// Gli identifier già collegati: si mostrano ma non si re-importano.
    private var linkedIdentifiers: Set<String> {
        Set(existingContacts.compactMap(\.contactIdentifier))
    }

    private var filtered: [ContactsImportService.DeviceContact] {
        guard !search.isEmpty else { return deviceContacts }
        return deviceContacts.filter {
            $0.fullName.localizedCaseInsensitiveContains(search)
                || $0.email.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView("Lettura dei Contatti…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .denied:
                    DSEmptyState(
                        icon: "person.crop.circle.badge.xmark",
                        title: "Accesso ai Contatti negato",
                        subtitle: "Per importare la rubrica, consenti l'accesso ai Contatti nelle impostazioni di sistema."
                    )
                case .ready:
                    contactsList
                }
            }
            .searchable(text: $search, prompt: "Cerca nella rubrica")
            .navigationTitle("Importa dai Contatti")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importa \(selection.count)") { importSelected() }
                        .disabled(selection.isEmpty)
                }
            }
            .task { await load() }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
    }

    private var contactsList: some View {
        List {
            ForEach(filtered) { device in
                row(device)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func row(_ device: ContactsImportService.DeviceContact) -> some View {
        let isLinked = linkedIdentifiers.contains(device.id)
        let isSelected = selection.contains(device.id)
        Button {
            guard !isLinked else { return }
            if isSelected {
                selection.remove(device.id)
            } else {
                selection.insert(device.id)
            }
        } label: {
            HStack(spacing: DS.m) {
                Image(systemName: isLinked
                      ? "checkmark.seal.fill"
                      : isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isLinked ? .green : isSelected
                                     ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.fullName)
                        .font(.dsMeta.weight(.medium))
                        .foregroundStyle(isLinked ? .secondary : .primary)
                    if !device.email.isEmpty || !device.phone.isEmpty {
                        Text(device.email.isEmpty ? device.phone : device.email)
                            .font(.dsCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isLinked {
                    Text("Già importato")
                        .font(.dsCaption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard await ContactsImportService.requestAccess() else {
            phase = .denied
            return
        }
        let fetched = await Task.detached(priority: .userInitiated) {
            (try? ContactsImportService.fetchDeviceContacts()) ?? []
        }.value
        deviceContacts = fetched
        phase = .ready
    }

    private func importSelected() {
        let picks = deviceContacts.filter { selection.contains($0.id) }
        do {
            let (workspace, _) = try SeedService.ensureSeed(in: modelContext)
            let workspaceID = UUID(uuidString: scopeRaw) ?? workspace.id
            try ContactsImportService.importContacts(
                picks, workspaceID: workspaceID, into: modelContext
            )
            dismiss()
        } catch {
            assertionFailure("Contacts import failed: \(error)")
        }
    }
}

#Preview {
    ContactsImportView()
        .modelContainer(PreviewSampleData.make().container)
}
