import SwiftUI
import SwiftData

/// F3 — un'etichetta come destinazione di navigazione: tutte le attività
/// che la portano, aperte prima, fatte in coda. Stessa grammatica delle
/// smart list (D70): lo stack lo fornisce l'host.
struct TaggedTasksView: View {
    @Bindable var tag: Tag

    @State private var showsManager = false

    private var tasks: [TodoTask] {
        tag.tasks
            .filter { $0.deletedAt == nil && !$0.isTemplate }
            .sorted {
                ($0.isDone ? 1 : 0, $0.dueAt ?? .distantFuture, $1.priorityRaw)
                    < ($1.isDone ? 1 : 0, $1.dueAt ?? .distantFuture, $0.priorityRaw)
            }
    }

    var body: some View {
        Group {
            if tasks.isEmpty {
                DSEmptyState(
                    icon: "number",
                    title: "Nessuna attività",
                    subtitle: "Scrivi #\(tag.name) in un'attività per etichettarla."
                )
            } else {
                List {
                    ForEach(tasks, id: \.id) { task in
                        TaskOpenLink(task: task) {
                            TaskRow(task: task) {
                                withAnimation(.dsSoft) { task.toggleDone() }
                            }
                        }
                        .taskContextMenu(task)
                    }
                }
            }
        }
        .navigationTitle("#\(tag.name)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    showsManager = true
                } label: {
                    Label("Gestisci etichette", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showsManager) {
            TagManagerView()
        }
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return NavigationStack {
        if let tag = try? preview.container.mainContext.fetch(
            FetchDescriptor<Tag>()
        ).first {
            TaggedTasksView(tag: tag)
        }
    }
    .modelContainer(preview.container)
}
