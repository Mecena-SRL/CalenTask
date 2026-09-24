import SwiftUI
import SwiftData

/// Soglie di presentazione del dettaglio attività (apertura adattiva allo
/// spazio): sopra `inspectorMinWidth` sta comodo come colonna destra; sotto
/// (ma ancora regular) conviene un popup modale; in compact è una pagina.
enum TaskPanel {
    /// Più bassa della soglia del pannello Oggi (1240): aprire un'attività è
    /// un gesto voluto, ha la precedenza sullo spazio rispetto al pannello.
    static let inspectorMinWidth: CGFloat = 1040
}

/// F14/F31 — il dettaglio attività come colonna destra (Mac/iPad regular):
/// si apre da Rapida, Calendario e viste progetto senza coprire il contesto.
/// Condivide lo slot inspector con il pannello Oggi (D74).
struct TaskInspectorView: View {
    let taskID: UUID
    var onClose: () -> Void

    @Query private var tasks: [TodoTask]

    init(taskID: UUID, onClose: @escaping () -> Void) {
        self.taskID = taskID
        self.onClose = onClose
        _tasks = Query(filter: #Predicate<TodoTask> {
            $0.id == taskID && $0.deletedAt == nil
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Attività")
                    .font(.dsSectionTitle)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chiudi dettaglio")
            }
            .padding(.horizontal, DS.l)
            .padding(.vertical, DS.m)

            Divider()

            if let task = tasks.first {
                TaskDetailView(task: task)
                    // Il titolo lo dà già la testata dell'inspector.
                    .navigationTitle("")
            } else {
                DSEmptyState(
                    icon: "questionmark.circle",
                    title: "Attività non trovata",
                    subtitle: "Potrebbe essere stata eliminata."
                )
            }
        }
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return TaskInspectorView(taskID: preview.tasks[0].id, onClose: {})
        .modelContainer(preview.container)
}
