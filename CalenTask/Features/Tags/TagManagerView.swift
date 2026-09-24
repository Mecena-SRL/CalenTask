import SwiftUI
import SwiftData

/// Il configuratore personale delle etichette (D21): per ogni #etichetta
/// scegli il colore, rinomini o elimini. Le card prendono il colore della
/// prima etichetta trovata nel testo.
struct TagManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var tags: [Tag]

    @Query(filter: #Predicate<Workspace> { $0.deletedAt == nil },
           sort: \Workspace.createdAt)
    private var workspaces: [Workspace]

    var body: some View {
        NavigationStack {
            Group {
                if tags.isEmpty {
                    DSEmptyState(
                        icon: "number",
                        title: "Nessuna etichetta",
                        subtitle: "Scrivi #etichetta nel titolo o nelle note di un'attività: comparirà qui e potrai darle un colore."
                    )
                } else {
                    List {
                        ForEach(workspaces, id: \.id) { workspace in
                            let scoped = tags.filter { $0.workspaceID == workspace.id }
                            if !scoped.isEmpty {
                                Section(workspace.name) {
                                    ForEach(scoped, id: \.id) { tag in
                                        TagEditorRow(tag: tag)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Etichette")
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
}

private struct TagEditorRow: View {
    @Bindable var tag: Tag

    var body: some View {
        HStack(spacing: DS.m) {
            Menu {
                palettePicker
            } label: {
                Circle()
                    .fill(Color(hex: tag.colorHex))
                    .frame(width: 22, height: 22)
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(0.1))
                    }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Text("#")
                .font(.dsMeta.weight(.semibold))
                .foregroundStyle(Color(hex: tag.colorHex))
            TextField("Nome", text: Binding(
                get: { tag.name },
                set: { tag.name = $0.lowercased().replacingOccurrences(of: " ", with: "-")
                       tag.updatedAt = .now }
            ))
            .textFieldStyle(.plain)
            .font(.dsMeta)

            Spacer()
            TagChip(tag: tag)
            Button(role: .destructive) {
                withAnimation {
                    tag.deletedAt = .now
                    tag.updatedAt = .now
                }
            } label: {
                Image(systemName: "trash")
                    .font(.dsCaption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var palettePicker: some View {
        ForEach(TagService.defaultPalette + ["#000000", "#92400E", "#365314", "#1E3A8A"],
                id: \.self) { hex in
            Button {
                tag.colorHex = hex
                tag.updatedAt = .now
            } label: {
                Label {
                    Text(hex == tag.colorHex ? "Selezionato" : hex)
                } icon: {
                    Image(systemName: hex == tag.colorHex ? "checkmark.circle.fill" : "circle.fill")
                        .foregroundStyle(Color(hex: hex))
                }
            }
        }
    }
}

#Preview {
    TagManagerView()
        .modelContainer(PreviewSampleData.make().container)
}
