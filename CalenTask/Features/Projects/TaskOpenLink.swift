import SwiftUI

/// F14/F31 — apre il dettaglio di un task nel modo giusto per lo spazio
/// disponibile: lo segnala al router (`inspect`) quando c'è una colonna destra
/// possibile — Mac e iPad regular — e lascia che la shell scelga tra inspector
/// (largo) e popup (stretto); in compact (iPhone) è una pagina nello stack.
struct TaskOpenLink<Content: View>: View {
    @Environment(AppRouter.self) private var router
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    let task: TodoTask
    @ViewBuilder var label: Content

    var body: some View {
        #if os(macOS)
        inspectButton
        #else
        if horizontalSizeClass == .regular {
            inspectButton
        } else {
            NavigationLink {
                TaskDetailView(task: task)
            } label: {
                label
            }
            .buttonStyle(.plain)
        }
        #endif
    }

    /// Non apre una pagina: passa l'attività al router, che la mostra come
    /// colonna destra (spazio) o popup modale (poco spazio) — vedi ShellSplitView.
    private var inspectButton: some View {
        Button {
            router.inspect(taskID: task.id)
        } label: {
            label
        }
        .buttonStyle(.plain)
    }
}
