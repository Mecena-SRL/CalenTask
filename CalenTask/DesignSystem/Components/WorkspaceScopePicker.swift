import SwiftUI
import SwiftData

/// Lo scope di lavoro globale (D44): "su cosa sto guardando" — tutti gli
/// spazi o uno solo. UN controllo, identico ovunque, persistito una volta.
enum WorkspaceScope {
    static let storageKey = "globalWorkspaceScope"

    /// "all" oppure l'UUID del workspace.
    static func matches(_ workspaceID: UUID, raw: String) -> Bool {
        raw == "all" || raw == workspaceID.uuidString
    }

    static func filter<T>(_ items: [T], raw: String, id: (T) -> UUID) -> [T] {
        guard raw != "all" else { return items }
        return items.filter { id($0).uuidString == raw }
    }

    /// Dove atterra una nuova attività/progetto senza una destinazione
    /// esplicita (A2): lo spazio che stai guardando, se ne stai guardando
    /// uno solo; altrimenti lo spazio personale. Un solo resolver, usato da
    /// ogni punto di creazione, così creare non ti fa più "perdere" ciò che
    /// appena creato dallo spazio attivo.
    static func creationTarget(raw: String, workspaces: [Workspace]) -> Workspace? {
        if raw != "all", let id = UUID(uuidString: raw),
           let match = workspaces.first(where: { $0.id == id && $0.deletedAt == nil }) {
            return match
        }
        return workspaces.first { $0.isPersonal && $0.deletedAt == nil }
    }
}

/// Switcher di spazio (D50, ripensato in F1/F17): in sidebar apre un popover
/// ricco — una card per spazio con colore, contatore e stato attivo — invece
/// del menu testuale; in toolbar resta il menu compatto.
struct WorkspaceScopePicker: View {
    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    @State private var isCreating = false
    @State private var editingWorkspace: Workspace?
    @State private var showsSwitcher = false

    @Query(filter: #Predicate<Workspace> { $0.deletedAt == nil },
           sort: \Workspace.createdAt)
    private var workspaces: [Workspace]

    @Query(filter: TodoTask.openPredicate)
    private var openTasks: [TodoTask]

    /// Compact = toolbar; expanded = testata della sidebar.
    var isCompact = true

    private var current: Workspace? {
        workspaces.first { $0.id.uuidString == scopeRaw }
    }

    private var tint: Color {
        current.map { Color(hex: $0.colorHex) } ?? .accentColor
    }

    private var label: String {
        current?.name ?? "Tutti gli spazi"
    }

    var body: some View {
        Group {
            if isCompact {
                compactMenu
            } else {
                expandedButton
            }
        }
        .sheet(isPresented: $isCreating) {
            WorkspaceEditorView()
        }
        .sheet(item: $editingWorkspace) { workspace in
            WorkspaceEditorView(workspace: workspace)
        }
    }

    // MARK: Toolbar (iPhone)

    private var compactMenu: some View {
        Menu {
            Picker("Spazio", selection: $scopeRaw.animation(.dsQuick)) {
                Label("Tutti gli spazi", systemImage: "square.grid.2x2")
                    .tag("all")
                Divider()
                ForEach(workspaces, id: \.id) { workspace in
                    Label(
                        workspace.name,
                        systemImage: workspace.isPersonal ? "person" : "building.2"
                    )
                    .tag(workspace.id.uuidString)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button {
                isCreating = true
            } label: {
                Label("Nuovo spazio…", systemImage: "plus")
            }
        } label: {
            HStack(spacing: DS.xs + 2) {
                Circle().fill(tint.gradient).frame(width: 9, height: 9)
                Text(label)
                    .font(.dsMeta.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: true)
        .dsHoverHighlight()
    }

    // MARK: Sidebar (Mac/iPad)

    private var expandedButton: some View {
        Button {
            showsSwitcher = true
        } label: {
            HStack(spacing: DS.s + 2) {
                avatar(for: current, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(.dsMeta.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(current == nil
                         ? "\(workspaces.count) spazi · \(openTasks.count) aperte"
                         : "\(openCount(in: current)) aperte")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, DS.xs + 2)
            .padding(.horizontal, DS.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHoverHighlight()
        .popover(isPresented: $showsSwitcher, arrowEdge: .bottom) {
            switcherPopover
        }
    }

    /// Il popover: ogni spazio è una card viva — colore, contatore, attivo.
    private var switcherPopover: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Spazi di lavoro")
                .font(.dsCaption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.s)
                .padding(.top, DS.xs)

            scopeRow(nil)
            Divider().padding(.vertical, DS.xs)
            ForEach(workspaces, id: \.id) { workspace in
                scopeRow(workspace)
            }
            Divider().padding(.vertical, DS.xs)
            HStack(spacing: DS.s) {
                Button {
                    showsSwitcher = false
                    isCreating = true
                } label: {
                    Label("Nuovo spazio", systemImage: "plus")
                        .font(.dsCaption.weight(.medium))
                }
                .buttonStyle(.borderless)
                Spacer()
                if let current {
                    Button {
                        showsSwitcher = false
                        editingWorkspace = current
                    } label: {
                        Label("Modifica", systemImage: "pencil")
                            .font(.dsCaption.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, DS.s)
            .padding(.bottom, DS.xs)
        }
        .padding(DS.s)
        .frame(width: 280)
    }

    @ViewBuilder
    private func scopeRow(_ workspace: Workspace?) -> some View {
        let isActive = workspace.map { $0.id.uuidString == scopeRaw } ?? (scopeRaw == "all")
        Button {
            withAnimation(.dsQuick) {
                scopeRaw = workspace?.id.uuidString ?? "all"
            }
            showsSwitcher = false
        } label: {
            HStack(spacing: DS.s + 2) {
                avatar(for: workspace, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(workspace?.name ?? "Tutti gli spazi")
                        .font(.dsMeta.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle(for: workspace))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(workspace.map { Color(hex: $0.colorHex) } ?? .accentColor)
                }
            }
            .padding(DS.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isActive ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: DS.Radius.small)
        )
        .dsHoverHighlight()
    }

    private func subtitle(for workspace: Workspace?) -> String {
        guard let workspace else {
            return "Vista combinata · \(openTasks.count) aperte"
        }
        let kind = workspace.isPersonal ? "Personale" : "Condiviso"
        return "\(kind) · \(openCount(in: workspace)) aperte"
    }

    private func openCount(in workspace: Workspace?) -> Int {
        guard let workspace else { return openTasks.count }
        return openTasks.count { $0.workspaceID == workspace.id }
    }

    /// Avatar dello scope: iniziale su gradiente per uno spazio,
    /// griglia neutra per "tutti".
    @ViewBuilder
    private func avatar(for workspace: Workspace?, size: CGFloat) -> some View {
        if let workspace {
            Circle()
                .fill(Color(hex: workspace.colorHex).gradient)
                .frame(width: size, height: size)
                .overlay {
                    Text(String(workspace.name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.46, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                }
        } else {
            Circle()
                .fill(.quaternary)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        WorkspaceScopePicker(isCompact: true)
        WorkspaceScopePicker(isCompact: false)
    }
    .padding()
    .modelContainer(PreviewSampleData.make().container)
}
