import SwiftUI
import SwiftData

/// La sidebar ricca (D51), ora CONDIVISA tra Mac e iPad (D70): sezioni con
/// icone piene colorate e badge vivi, progetti, liste smart. Testata =
/// switcher spazi (D50), footer = account → Impostazioni.
struct SidebarView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    private var configuration: AppConfiguration { .decode(configurationRaw) }

    @Query(filter: TodoTask.inboxPredicate)
    private var inboxTasks: [TodoTask]

    @Query(filter: TodoTask.openPredicate)
    private var allOpenTasks: [TodoTask]

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var allProjects: [Project]

    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil },
           sort: \UserProfile.createdAt)
    private var profiles: [UserProfile]

    // Smart list pinnate in sidebar (S4/D62).
    @Query(filter: #Predicate<SavedView> { $0.deletedAt == nil && $0.projectID == nil },
           sort: \SavedView.createdAt)
    private var allSavedViews: [SavedView]
    @State private var isCreatingSmartList = false

    // F3 — le etichette navigabili come le liste.
    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var allTags: [Tag]
    @State private var showsTagManager = false

    // F2 — il mini-mese in fondo: si sfoglia senza lasciare la sidebar.
    @State private var miniMonth = Date.now.startOfDay

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    @AppStorage(DSAppearance.storageKey) private var appearanceRaw = DSAppearance.auto.rawValue

    // G2 — le sezioni si riducono, e la scelta resta.
    @AppStorage("sidebarShowsFavorites") private var showsFavorites = true
    @AppStorage("sidebarShowsProjects") private var showsProjects = true
    @AppStorage("sidebarShowsLists") private var showsLists = true
    @AppStorage("sidebarShowsTags") private var showsTags = true

    private var smartLists: [SavedView] {
        WorkspaceScope.filter(allSavedViews, raw: scopeRaw, id: \.workspaceID)
    }

    private var tags: [Tag] {
        WorkspaceScope.filter(allTags, raw: scopeRaw, id: \.workspaceID)
    }

    private var openTasks: [TodoTask] {
        WorkspaceScope.filter(allOpenTasks, raw: scopeRaw, id: \.workspaceID)
    }

    private var projects: [Project] {
        WorkspaceScope.filter(allProjects, raw: scopeRaw, id: \.workspaceID)
    }

    private var favoriteProjects: [Project] {
        projects.filter(\.isFavorite)
    }

    private var otherProjects: [Project] {
        projects.filter { !$0.isFavorite }
    }

    private var selection: Binding<AppDestination?> {
        @Bindable var router = router
        return Binding(
            get: { router.destination },
            set: { if let destination = $0 { router.destination = destination } }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(configuration.navigationSections) { section in
                    Label {
                        Text(section.label)
                            .font(.dsMeta.weight(.medium))
                    } icon: {
                        Image(systemName: section.filledSystemImage)
                            .foregroundStyle(section.tint)
                    }
                    .badge(badgeCount(for: section))
                    .tag(AppDestination.section(section))
                }
            }

            // D75 — i preferiti sempre sott'occhio, sopra il resto.
            // G2 — ogni sezione si riduce dal suo header.
            if configuration.isEnabled(.projects) && !favoriteProjects.isEmpty {
                Section(isExpanded: $showsFavorites) {
                    ForEach(favoriteProjects, id: \.id) { project in
                        sidebarProjectRow(project)
                            .tag(AppDestination.project(project.id))
                    }
                } header: {
                    Text("Preferiti")
                }
            }

            if configuration.isEnabled(.projects) {
            Section(isExpanded: $showsProjects) {
                ForEach(otherProjects, id: \.id) { project in
                    sidebarProjectRow(project)
                        .tag(AppDestination.project(project.id))
                }
            } header: {
                Text("Progetti")
            }

            }
            if configuration.isEnabled(.smartLists) {
            Section(isExpanded: $showsLists) {
                ForEach(smartLists, id: \.id) { list in
                    smartListRow(list)
                        .tag(AppDestination.smartList(list.id))
                }
                Button {
                    isCreatingSmartList = true
                } label: {
                    Label {
                        Text("Nuova lista…")
                            .font(.dsMeta)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "plus")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Liste")
            }

            }
            // F3 — Etichette alla pari di Progetti e Liste.
            if configuration.isEnabled(.tags) && !tags.isEmpty {
                Section(isExpanded: $showsTags) {
                    ForEach(tags, id: \.id) { tag in
                        tagRow(tag)
                            .tag(AppDestination.tag(tag.id))
                    }
                    Button {
                        showsTagManager = true
                    } label: {
                        Label {
                            Text("Gestisci…")
                                .font(.dsMeta)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Etichette")
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $isCreatingSmartList) {
            SmartListEditorView()
        }
        .sheet(isPresented: $showsTagManager) {
            TagManagerView()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Lo scope globale vive qui: un posto solo, sempre visibile (D44).
            WorkspaceScopePicker(isCompact: false)
                .padding(.horizontal, DS.s)
                .padding(.bottom, DS.xs)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if configuration.isEnabled(.sidebarMiniCalendar) { sidebarMiniMonth }
                sidebarAccountFooter
            }
        }
        #if os(macOS)
        // Tema "misto": sidebar scura, contenuto secondo sistema (D47).
        .modifier(DSMixedSchemeModifier(
            isActive: appearanceRaw == DSAppearance.mixed.rawValue
        ))
        #endif
    }

    // MARK: Righe

    private func sidebarProjectRow(_ project: Project) -> some View {
        let open = project.tasks.filter { $0.deletedAt == nil && !$0.isDone && !$0.isPhase && !$0.isTemplate }.count
        return HStack(spacing: DS.s) {
            Circle()
                .fill(Color(hex: project.colorHex).gradient)
                .frame(width: 10, height: 10)
            Text(project.name)
                .font(.dsMeta)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            if open > 0 {
                Text("\(open)")
                    .font(.dsNumeric)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
        }
        .contextMenu {
            ProjectMenuContent(project: project) { viewType in
                UserDefaults.standard.set(viewType.rawValue, forKey: "lastProjectViewType")
                router.open(projectID: project.id)
            }
        }
    }

    private func tagRow(_ tag: Tag) -> some View {
        let count = tag.tasks.filter { $0.deletedAt == nil && !$0.isDone && !$0.isTemplate }.count
        return Label {
            Text(tag.name)
                .font(.dsMeta)
                .foregroundStyle(.primary)
                .lineLimit(1)
        } icon: {
            Image(systemName: "number")
                .foregroundStyle(Color(hex: tag.colorHex))
        }
        .badge(count)
    }

    private func smartListRow(_ list: SavedView) -> some View {
        let filters = list.filters
        let count = allOpenTasks
            .filter { $0.workspaceID == list.workspaceID && filters.matches($0) }
            .count
        return Label {
            Text(list.name)
                .font(.dsMeta)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(Color.accentColor)
        }
        .badge(count)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation(.dsSoft) {
                    if router.destination == .smartList(list.id) {
                        router.go(.quick)
                    }
                    list.deletedAt = .now
                    list.updatedAt = .now
                }
            } label: {
                Label("Elimina lista", systemImage: "trash")
            }
        }
    }

    private func badgeCount(for section: AppSection) -> Int {
        switch section {
        case .quick: openTasks.count
        case .dashboard: todayCount
        case .inbox: WorkspaceScope.filter(inboxTasks, raw: scopeRaw, id: \.workspaceID).count
        case .calendar: todayEventCount
        case .projects: 0
        case .people: 0
        }
    }

    private var todayCount: Int {
        let calendar = Calendar.current
        return openTasks.filter { task in
            let dates = [task.startAt, task.dueAt, task.remindAt].compactMap(\.self)
            return dates.contains { calendar.isDateInToday($0) }
        }.count
    }

    private var todayEventCount: Int {
        let calendar = Calendar.current
        return openTasks.filter { task in
            task.kind == .event && task.startAt.map { calendar.isDateInToday($0) } == true
        }.count
    }

    // MARK: Mini-mese (F2)

    /// Pallini = giornate con attività (inizio o scadenza), nello scope attivo.
    private var miniMonthCounts: [Date: Int] {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for task in openTasks {
            for date in [task.startAt, task.dueAt].compactMap({ $0 }) {
                counts[calendar.startOfDay(for: date), default: 0] += 1
            }
        }
        return counts
    }

    private var sidebarMiniMonth: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            HStack(spacing: DS.xs) {
                Button {
                    withAnimation(.dsQuick) { miniMonth = Date.now.startOfDay }
                } label: {
                    Text(miniMonth.formatted(
                        Calendar.current.isDate(miniMonth, equalTo: .now, toGranularity: .year)
                            ? .dateTime.month(.wide)
                            : .dateTime.month(.wide).year()
                    ).capitalized)
                    .font(.dsCaption.weight(.semibold))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help("Torna al mese corrente")
                Spacer()
                Button { shiftMiniMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Button { shiftMiniMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            MiniMonthView(
                month: miniMonth,
                selectedDay: .now.startOfDay,
                countsByDay: miniMonthCounts,
                showsTitle: false,
                onSelectDay: { day in router.open(calendarDay: day) }
            )
        }
        .padding(.horizontal, DS.m)
        .padding(.vertical, DS.s)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func shiftMiniMonth(_ delta: Int) {
        withAnimation(.dsQuick) {
            miniMonth = Calendar.current.date(
                byAdding: .month, value: delta, to: miniMonth
            ) ?? miniMonth
        }
    }

    // MARK: Account

    /// L'account a un click dal fondo della sidebar (apre Impostazioni).
    private var sidebarAccountFooter: some View {
        Group {
            #if os(macOS)
            SettingsLink { accountFooterLabel }
            #else
            Button {
                router.isSettingsOpen = true
            } label: {
                accountFooterLabel
            }
            #endif
        }
        .buttonStyle(.plain)
        .padding(DS.m)
        .background(.ultraThinMaterial)
    }

    private var accountFooterLabel: some View {
        HStack(spacing: DS.s) {
            AccountAvatar(name: currentUserName, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(currentUserName)
                    .font(.dsCaption.weight(.semibold))
                Text(StoreMode.isCloudKit
                     ? "iCloud attivo" : "Solo questo dispositivo")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "gearshape")
                .font(.dsCaption)
                .foregroundStyle(.tertiary)
        }
        .padding(DS.s)
        .background(DSColor.surfaceSecondary.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: DS.Radius.small))
        .contentShape(Rectangle())
    }

    private var currentUserName: String {
        let currentID = UserDefaults.standard.string(forKey: SeedService.userDefaultsKey)
            .flatMap(UUID.init(uuidString:))
        return (profiles.first { $0.id == currentID } ?? profiles.first)?.name ?? "Account"
    }
}

#Preview {
    NavigationSplitView {
        SidebarView()
    } detail: {
        Text("Dettaglio")
    }
    .environment(AppRouter())
    .modelContainer(PreviewSampleData.make().container)
}
