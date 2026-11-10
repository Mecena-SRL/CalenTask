import Foundation
import SwiftData
import SwiftUI

/// Impostazioni › Cestino (#22): le attività eliminate si possono ripristinare
/// (con le sotto-attività) o cancellare per sempre; dopo 30 giorni le elimina
/// `TrashService.purgeExpired`.
struct TrashSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<TodoTask> { $0.deletedAt != nil },
        sort: \TodoTask.deletedAt, order: .reverse
    ) private var deleted: [TodoTask]
    @State private var confirmEmpty = false

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
                            Button("Ripristina") { task.restoreSubtree() }
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
                TrashService.deleteForever(deleted, in: modelContext)
            }
        }
    }
}
