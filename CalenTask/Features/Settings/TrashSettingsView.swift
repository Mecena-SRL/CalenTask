import Foundation
import SwiftData
import SwiftUI

/// Impostazioni › Cestino (#22): le attività eliminate si possono ripristinare
/// (con le sotto-attività) o cancellare per sempre; dopo 30 giorni le elimina
/// `TrashService.purgeExpired`.
struct TrashSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TodoTask> { $0.deletedAt != nil })
    private var trashed: [TodoTask]
    @State private var confirmEmpty = false

    /// Radici dei sottoalberi eliminati, le più recenti prima.
    private var deleted: [TodoTask] {
        trashed.filter { $0.parentTask?.deletedAt == nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var body: some View {
        Form {
            Section { SettingsPageHeader(page: .trash) }

            if deleted.isEmpty {
                Section {
                    Label("Il cestino è vuoto.", systemImage: "trash")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(deleted) { task in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title.isEmpty ? "Senza titolo" : task.title)
                                if let when = task.deletedAt {
                                    Text("Eliminata \(when.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Ripristina") { TrashService.restore(task) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                Section {
                    Button("Svuota cestino", role: .destructive) { confirmEmpty = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cestino")
        .confirmationDialog(
            "Eliminare per sempre \(deleted.count) attività?",
            isPresented: $confirmEmpty, titleVisibility: .visible
        ) {
            Button("Elimina per sempre", role: .destructive) {
                TrashService.emptyTrash(in: modelContext)
            }
        }
    }
}
