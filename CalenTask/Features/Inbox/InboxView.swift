import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var showsTriage = false
    @State private var filter: InboxFilter = .all
    /// F21 — la spiegazione si può congedare, ma di default c'è.
    @AppStorage("inboxHintDismissed") private var hintDismissed = false

    @Query(
        filter: TodoTask.inboxPredicate,
        sort: \TodoTask.createdAt,
        order: .reverse
    )
    private var tasks: [TodoTask]

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var projects: [Project]

    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil })
    private var people: [UserProfile]

    @Query(filter: #Predicate<Workspace> { $0.deletedAt == nil })
    private var workspaces: [Workspace]

    // A5 (audit account) — l'Inbox ereditava SEMPRE tutti gli spazi, mentre
    // Calendario/Dashboard/Progetti rispettano lo spazio attivo: il contatore
    // in Oggi poteva differire da ciò che si vedeva aprendo l'Inbox.
    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"

    private var scopedTasks: [TodoTask] {
        WorkspaceScope.filter(tasks, raw: scopeRaw, id: \.workspaceID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if scopedTasks.isEmpty {
                    DSEmptyState(
                        icon: "tray",
                        title: "Inbox vuota",
                        subtitle: "Cattura un'idea al volo: la sviluppi quando vuoi.",
                        actionTitle: "Nuova attività",
                        action: { router.isQuickCaptureOpen = true }
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem {
                    // S4/D61: il rituale del triage — una carta alla volta.
                    Button {
                        showsTriage = true
                    } label: {
                        Label("Smista", systemImage: "rectangle.stack.badge.play")
                    }
                    .disabled(scopedTasks.isEmpty)
                }
                ToolbarItem {
                    Button {
                        router.isQuickCaptureOpen = true
                    } label: {
                        Label("Nuova attività", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showsTriage) {
                TriageFlowView()
            }
        }
    }

    // MARK: Lista

    private var list: some View {
        // Barra filtri SOPRA la List, non come `.safeAreaInset` (su macOS
        // l'inset di una List ospitata innescava un ciclo di vincoli).
        VStack(spacing: 0) {
            InboxFilterBar(selection: $filter, counts: filterCounts)
            Divider()
            List {
                if !hintDismissed {
                    hintSection
                }
                if filteredTasks.isEmpty {
                    Section {
                        Text("Niente in «\(filter.label)».")
                            .font(.dsMeta)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, DS.l)
                    }
                } else {
                    ForEach(groups) { group in
                        Section(group.bucket.title) {
                            ForEach(group.items, id: \.id) { task in
                                NavigationLink {
                                    TaskDetailView(task: task)   // "Sviluppa": full editor
                                } label: {
                                    TriageRow(
                                        task: task, projects: projects,
                                        provenance: provenance(for: task)
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var hintSection: some View {
        Section {
            HStack(alignment: .top, spacing: DS.m) {
                DSIconTile(systemImage: "tray.and.arrow.down",
                           tint: AppSection.inbox.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Qui atterra tutto ciò che catturi senza progetto.")
                        .font(.dsMeta.weight(.medium))
                    Text("Ogni riga mostra la sua origine: chi l'ha catturata, una richiesta esterna, una delega. Filtra per origine in alto, oppure «Smista» per deciderle una alla volta.")
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.dsQuick) { hintDismissed = true }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nascondi spiegazione")
            }
            .padding(.vertical, DS.xs)
        }
    }

    // MARK: Derivazioni

    private var meID: UUID? {
        UserDefaults.standard.string(forKey: SeedService.userDefaultsKey)
            .flatMap(UUID.init(uuidString:))
    }

    private var peopleMap: [UUID: String] {
        Dictionary(people.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private var workspaceMap: [UUID: Workspace] {
        Dictionary(workspaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var filteredTasks: [TodoTask] {
        scopedTasks.filter { filter.matches($0, meID: meID) }
    }

    private var filterCounts: [InboxFilter: Int] {
        var counts: [InboxFilter: Int] = [:]
        for candidate in InboxFilter.allCases {
            counts[candidate] = scopedTasks.count { candidate.matches($0, meID: meID) }
        }
        return counts
    }

    private var groups: [InboxGroup] {
        let grouped = Dictionary(grouping: filteredTasks) {
            InboxDateBucket.bucket(for: $0.createdAt)
        }
        return InboxDateBucket.allCases.compactMap { bucket in
            guard let items = grouped[bucket], !items.isEmpty else { return nil }
            return InboxGroup(bucket: bucket, items: items)
        }
    }

    private func provenance(for task: TodoTask) -> TaskProvenance {
        task.provenance(meID: meID, people: peopleMap, workspaces: workspaceMap)
    }
}

/// Un gruppo dell'Inbox = una fascia temporale con i suoi task.
private struct InboxGroup: Identifiable {
    let bucket: InboxDateBucket
    let items: [TodoTask]
    var id: Int { bucket.rawValue }
}

/// Barra dei filtri per origine: pillole con contatore, scorrevoli. Mostra solo
/// le origini presenti (più «Tutto» e quella selezionata), così resta pulita.
private struct InboxFilterBar: View {
    @Binding var selection: InboxFilter
    let counts: [InboxFilter: Int]

    private var visible: [InboxFilter] {
        InboxFilter.allCases.filter {
            $0 == .all || $0 == selection || (counts[$0] ?? 0) > 0
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DS.s) {
                ForEach(visible) { filter in
                    pill(filter)
                }
            }
            .padding(.horizontal, DS.l)
            .padding(.vertical, DS.s)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }

    private func pill(_ filter: InboxFilter) -> some View {
        let isOn = selection == filter
        let count = counts[filter] ?? 0
        return Button {
            withAnimation(.dsQuick) { selection = filter }
        } label: {
            HStack(spacing: DS.xs + 1) {
                Image(systemName: filter.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(filter.label)
                    .font(.dsCaption.weight(.medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.dsNumeric)
                        .foregroundStyle(isOn ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                }
            }
            .padding(.horizontal, DS.m)
            .padding(.vertical, DS.xs + 2)
            .background(
                isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.6)),
                in: Capsule()
            )
            .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    InboxView()
        .environment(AppRouter())
        .modelContainer(PreviewSampleData.make().container)
}
