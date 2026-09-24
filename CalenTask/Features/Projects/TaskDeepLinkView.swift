import SwiftUI
import SwiftData

/// Resolves a task ID from a notification tap and shows its editor.
struct TaskDeepLinkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID

    var body: some View {
        NavigationStack {
            Group {
                if let task = resolveTask() {
                    TaskDetailView(task: task)
                } else {
                    DSEmptyState(
                        icon: "questionmark.circle",
                        title: "Attività non trovata",
                        subtitle: "Potrebbe essere stata eliminata."
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    private func resolveTask() -> TodoTask? {
        let id = taskID
        var descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
