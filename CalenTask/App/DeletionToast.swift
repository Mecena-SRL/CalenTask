import SwiftUI
import SwiftData

extension TodoTask {
    /// #22 — eliminazione dall'interfaccia (menu, swipe, dettaglio): una fase
    /// si porta dietro il sottoalbero, e compare il toast "Eliminata · Annulla".
    @MainActor
    func deleteWithUndo() {
        if isPhase {
            softDeleteSubtree()
        } else {
            softDelete()
        }
        AppRouter.shared.announceDeletion(taskID: id, title: title)
    }
}

/// #22 — "Eliminata · Annulla": per qualche secondo dopo un'eliminazione si
/// può rimettere la task (col suo sottoalbero) dove stava. Poi resta il Cestino.
struct DeletionToast: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    let notice: DeletionNotice

    static let visibleFor: Duration = .seconds(6)

    var body: some View {
        HStack(spacing: DS.m) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text("Eliminata: \(notice.title)")
                .font(.dsMeta)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: DS.s)
            Button("Annulla") { undo() }
                .font(.dsMeta.weight(.semibold))
                .buttonStyle(.borderless)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi")
        }
        .padding(.horizontal, DS.l)
        .padding(.vertical, DS.m)
        .frame(maxWidth: 480)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(DSColor.hairline) }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, DS.l)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .task(id: notice.id) {
            do {
                try await Task.sleep(for: Self.visibleFor)
            } catch {
                return   // sostituito da un'altra eliminazione o chiuso a mano
            }
            if router.deletionNotice?.id == notice.id { dismiss() }
        }
    }

    private func undo() {
        withAnimation(.dsQuick) {
            TrashService.restore(taskID: notice.taskID, in: modelContext)
            router.deletionNotice = nil
        }
    }

    private func dismiss() {
        withAnimation(.dsQuick) { router.deletionNotice = nil }
    }
}
