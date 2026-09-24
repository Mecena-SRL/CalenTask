import SwiftUI
import SwiftData

/// Inbox row with inline triage: complete, set due date, move into a project.
/// Sotto il titolo mostra la PROVENIENZA (chi/da dove arriva il task, v8).
struct TriageRow: View {
    @Environment(\.modelContext) private var modelContext
    let task: TodoTask
    let projects: [Project]
    /// Provenienza già risolta dalla vista (niente fetch per riga).
    var provenance: TaskProvenance? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            TaskRow(task: task, showProject: false) {
                withAnimation(.dsSoft) { task.toggleDone() }
            }
            if let provenance {
                ProvenanceLabel(provenance: provenance)
                    .padding(.leading, 30)   // allinea sotto il titolo, oltre il check
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                withAnimation { task.softDelete() }
            } label: {
                Label("Elimina", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                task.setDue(.now.startOfDay)
            } label: {
                Label("Oggi", systemImage: "sun.max")
            }
            .tint(Color.accentColor)
        }
        // Il menu standard delle attività (D46) copre triage e oltre.
        .taskContextMenu(task)
    }
}
