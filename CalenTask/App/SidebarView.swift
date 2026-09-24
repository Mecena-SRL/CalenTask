import SwiftUI
import SwiftData

/// La sidebar ricca (D51), CONDIVISA tra Mac e iPad (D70). Testata = spazio
/// (D50) + ricerca e nuova attività; sezioni a tessera colorata con badge a
/// capsula; gruppi riducibili con l'azione rapida nell'intestazione;
/// in fondo mini-mese e account → Impostazioni.
///
/// #5 — L'involucro legge lo spazio scelto e lo passa al contenuto, che
/// filtra le attività nello STORE (query costruite nell'`init`).
///
/// Stabilità: niente `Section(isExpanded:)`. Su macOS, aggiungere o spostare
/// righe in un gruppo chiuso (nuovo progetto, preferito, lista) faceva
/// sollevare a NSOutlineView un'eccezione di coerenza → crash. Ora un gruppo
/// chiuso semplicemente non ha righe.
struct SidebarView: View {
    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"

    var body: some View {
        SidebarContent(workspaceID: WorkspaceScope.workspaceID(raw: scopeRaw))
    }
}

private struct SidebarContent: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    private var configuration: AppConfiguration { .decode(configurationRaw) }

    /// Inbox e attività aperte dello spazio scelto (tutti se nil).
    @Query private var inboxTasks: [TodoTask]
    @Query private var openTasks: [TodoTask]

    init(workspaceID: UUID?) {
        _inboxTasks = Query(filter: TodoTask.inboxPredicate(workspaceID: workspaceID))
        _openTasks = Query(filter: TodoTask.openPredicate(workspaceID: workspaceID))
    }

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

    @State private var isCreatingProject = false

    // F2 — il mini-mese in fondo: si sfoglia senza lasciare la sidebar.
    @State private var miniMonth = Date.now.startOfDay

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    @AppStorage(DSAppearance.storageKey) private var appearanceRaw = DSAppearance.auto.rawValue

    // G2 — i gruppi si riducono, e la scelta resta.
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

    private var projects: [Project] {
        WorkspaceScope.filter(allProjects, raw: scopeRaw, id: \.workspaceID)
    }

    private var selection: Binding<AppDestination?> {
        @Bindable var router = router
        return Binding(
            get: { router.destination },
            set: { if let destination = $0 { router.destination = destination } }
        )
    }

    var body: some View {
        let stats = OpenTaskStats(tasks: openTasks, calendar: .current)
        let openCounts = stats.byProject
        let scopedProjects = projects
        let favoriteProjects = scopedProjects.filter(\.isFavorite)
        let otherProjects = scopedProjects.filter { !$0.isFavorite }

        // Testata e piè di pagina FUORI dalla List, in una VStack (crash
        // 0.0.3/0.0.4 all'avvio): con `.safeAreaInset` sulla List della
        // sidebar, AppKit spostava le righe ospitate a ogni passaggio di
        // layout, ne invalidava la safe area e rifaceva i vincoli all'infinito
        // ("more Update Constraints in Window passes than there are views").
        VStack(spacing: 0) {
            sidebarHeader(openCount: stats.total)

            List(selection: selection) {
                Section {
                    ForEach(configuration.navigationSections) { section in
                        SidebarNavRow(
                            section: section,
                            count: badgeCount(for: section, stats: stats)
                        )
                        .tag(AppDestination.section(section))
                    }
                }

                // D75 — i preferiti sempre sott'occhio, sopra il resto.
                if configuration.isEnabled(.projects) && !favoriteProjects.isEmpty {
                    Section {
                        if showsFavorites {
                            ForEach(favoriteProjects, id: \.id) { project in
                                projectRow(project, openCount: openCounts[project.id] ?? 0)
                                    .tag(AppDestination.project(project.id))
                            }
                        }
                    } header: {
                        SidebarGroupHeader(
                            title: "Preferiti",
                            count: favoriteProjects.count,
                            isExpanded: $showsFavorites
                        )
                    }
                }

                if configuration.isEnabled(.projects) {
                    Section {
                        if showsProjects {
                            ForEach(otherProjects, id: \.id) { project in
                                projectRow(project, openCount: openCounts[project.id] ?? 0)
                                    .tag(AppDestination.project(project.id))
                            }
                            if scopedProjects.isEmpty {
                                SidebarPlaceholderRow(
                                    title: "Crea il primo progetto",
                                    systemImage: "plus.circle"
                                ) { isCreatingProject = true }
                            }
                        }
                    } header: {
                        SidebarGroupHeader(
                            title: "Progetti",
                            count: otherProjects.count,
                            isExpanded: $showsProjects,
                            accessory: SidebarGroupHeader.Accessory(systemImage: "plus", help: "Nuovo progetto") {
                                isCreatingProject = true
                            }
                        )
                    }
                }

                if configuration.isEnabled(.smartLists) {
                    Section {
                        if showsLists {
                            ForEach(smartLists, id: \.id) { list in
                                smartListRow(list)
                                    .tag(AppDestination.smartList(list.id))
                            }
                            if smartLists.isEmpty {
                                SidebarPlaceholderRow(
                                    title: "Nuova lista smart",
                                    systemImage: "plus.circle"
                                ) { isCreatingSmartList = true }
                            }
                        }
                    } header: {
                        SidebarGroupHeader(
                            title: "Liste",
                            count: smartLists.count,
                            isExpanded: $showsLists,
                            accessory: SidebarGroupHeader.Accessory(systemImage: "plus", help: "Nuova lista") {
                                isCreatingSmartList = true
                            }
                        )
                    }
                }

                // F3 — Etichette alla pari di Progetti e Liste.
                if configuration.isEnabled(.tags) && !tags.isEmpty {
                    Section {
                        if showsTags {
                            ForEach(tags, id: \.id) { tag in
                                tagRow(tag)
                                    .tag(AppDestination.tag(tag.id))
                            }
                        }
                    } header: {
                        SidebarGroupHeader(
                            title: "Etichette",
                            count: tags.count,
                            isExpanded: $showsTags,
                            accessory: SidebarGroupHeader.Accessory(systemImage: "slider.horizontal.3", help: "Gestisci etichette") {
                                showsTagManager = true
                            }
                        )
                    }
                }
            }
            .listStyle(.sidebar)

            VStack(spacing: DS.s) {
                if configuration.isEnabled(.sidebarMiniCalendar) {
                    sidebarMiniMonth(counts: stats.byDay)
                }
                sidebarAccountFooter
            }
            .padding(DS.s)
            .overlay(alignment: .top) { Divider() }
        }
        .sheet(isPresented: $isCreatingSmartList) {
            SmartListEditorView()
        }
        .sheet(isPresented: $showsTagManager) {
            TagManagerView()
        }
        .sheet(isPresented: $isCreatingProject) {
            NewProjectSheet()
        }
        // Un nuovo preferito non resta nascosto in un gruppo chiuso.
        .onChange(of: favoriteProjects.count) { old, new in
            if new > old { showsFavorites = true }
        }
        #if os(macOS)
        // Tema "misto": sidebar scura, contenuto secondo sistema (D47).
        .modifier(DSMixedSchemeModifier(
            isActive: appearanceRaw == DSAppearance.mixed.rawValue
        ))
        #endif
    }

    // MARK: Testata

    /// Lo scope globale vive qui (D44), con ricerca e cattura a un clic.
    private func sidebarHeader(openCount: Int) -> some View {
        VStack(spacing: DS.xs + 2) {
            WorkspaceScopePicker(isCompact: false, openCount: openCount)
            HStack(spacing: DS.xs + 2) {
                Button {
                    router.isCommandPaletteOpen = true
                } label: {
                    HStack(spacing: DS.xs + 2) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Cerca")
                            .font(.dsMeta)
                        Spacer(minLength: 0)
                        #if os(macOS)
                        Text("⌘K")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                        #endif
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DS.s)
                    .frame(height: 28)
                    .background(
                        Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Cerca ovunque (⌘K)")

                Button {
                    router.isQuickCaptureOpen = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            Color.accentColor.gradient,
                            in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Nuova attività (⌘N)")
                .accessibilityLabel("Nuova attività")
            }
            .padding(.horizontal, DS.xs)
        }
        .padding(.horizontal, DS.s)
        .padding(.bottom, DS.s)
    }

    // MARK: Righe

    private func projectRow(_ project: Project, openCount: Int) -> some View {
        HStack(spacing: DS.s) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(hex: project.colorHex).gradient)
                .frame(width: 10, height: 10)
                .frame(width: SidebarIconTile.size)
            Text(project.name)
                .font(.dsMeta)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: DS.xs)
            SidebarCountBadge(count: openCount)
        }
        .contentShape(Rectangle())
        .contextMenu {
            ProjectMenuContent(project: project) { viewType in
                UserDefaults.standard.set(viewType.rawValue, forKey: "lastProjectViewType")
                router.open(projectID: project.id)
            }
        }
    }

    private func tagRow(_ tag: Tag) -> some View {
        let count = tag.tasks.filter { $0.deletedAt == nil && !$0.isDone && !$0.isTemplate }.count
        return HStack(spacing: DS.s) {
            Image(systemName: "number")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: tag.colorHex))
                .frame(width: SidebarIconTile.size)
            Text(tag.name)
                .font(.dsMeta)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: DS.xs)
            SidebarCountBadge(count: count)
        }
        .contentShape(Rectangle())
    }

    private func smartListRow(_ list: SavedView) -> some View {
        let filters = list.filters
        let count = openTasks
            .filter { $0.workspaceID == list.workspaceID && filters.matches($0) }
            .count
        return HStack(spacing: DS.s) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: SidebarIconTile.size)
            Text(list.name)
                .font(.dsMeta)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: DS.xs)
            SidebarCountBadge(count: count)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                if router.destination == .smartList(list.id) {
                    router.go(.calendar)
                }
                list.deletedAt = .now
                list.updatedAt = .now
            } label: {
                Label("Elimina lista", systemImage: "trash")
            }
        }
    }

    private func badgeCount(for section: AppSection, stats: OpenTaskStats) -> Int {
        switch section {
        case .quick: stats.total
        case .dashboard: stats.today
        case .inbox: inboxTasks.count
        case .calendar: stats.todayEvents
        case .projects: 0
        case .people: 0
        }
    }

    // MARK: Mini-mese (F2)

    /// Pallini = giornate con attività (inizio o scadenza), nello scope attivo.
    private func sidebarMiniMonth(counts: [Date: Int]) -> some View {
        let isCurrentMonth = Calendar.current.isDate(miniMonth, equalTo: .now, toGranularity: .month)
        return VStack(alignment: .leading, spacing: DS.xs) {
            HStack(spacing: DS.xs) {
                Text(miniMonth.formatted(
                    Calendar.current.isDate(miniMonth, equalTo: .now, toGranularity: .year)
                        ? .dateTime.month(.wide)
                        : .dateTime.month(.wide).year()
                ).capitalized)
                .font(.dsCaption.weight(.semibold))
                .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if !isCurrentMonth {
                    Button("Oggi") {
                        withAnimation(.dsQuick) { miniMonth = Date.now.startOfDay }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                    .help("Torna al mese corrente")
                }
                miniMonthArrow("chevron.left", help: "Mese precedente") { shiftMiniMonth(-1) }
                miniMonthArrow("chevron.right", help: "Mese successivo") { shiftMiniMonth(1) }
            }
            MiniMonthView(
                month: miniMonth,
                selectedDay: .now.startOfDay,
                countsByDay: counts,
                showsTitle: false,
                onSelectDay: { day in router.open(calendarDay: day) }
            )
        }
        .padding(DS.s)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
        )
    }

    private func miniMonthArrow(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func shiftMiniMonth(_ delta: Int) {
        withAnimation(.dsQuick) {
            miniMonth = Calendar.current.date(
                byAdding: .month, value: delta, to: miniMonth
            ) ?? miniMonth
        }
    }

    // MARK: Account

    /// L'account a un clic dal fondo della sidebar (apre Impostazioni).
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
        .dsHoverHighlight(cornerRadius: DS.Radius.medium)
        .help("Account e impostazioni")
    }

    private var accountFooterLabel: some View {
        let status = syncStatus
        return HStack(spacing: DS.s) {
            AccountAvatar(name: currentUserName, size: 28)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(DSColor.surface, lineWidth: 1.5))
                        .offset(x: 1, y: 1)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(currentUserName)
                    .font(.dsCaption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(status.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "gearshape")
                .font(.dsCaption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DS.xs)
        .padding(.vertical, DS.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Stato EFFETTIVO dello store (A6): iCloud, iCloud in errore o locale.
    private var syncStatus: (label: String, color: Color) {
        if StoreMode.isCloudKit {
            return ("iCloud attivo", Color.green)
        }
        if StoreMode.cloudKitFailure != nil {
            return ("iCloud non disponibile", Color.orange)
        }
        return ("Solo questo dispositivo", Color.gray)
    }

    private var currentUserName: String {
        let currentID = UserDefaults.standard.string(forKey: SeedService.userDefaultsKey)
            .flatMap(UUID.init(uuidString:))
        return (profiles.first { $0.id == currentID } ?? profiles.first)?.name ?? "Account"
    }
}

// MARK: - Componenti

/// Icona di sezione su tessera colorata (come Impostazioni di sistema).
private struct SidebarIconTile: View {
    static let size: CGFloat = 22

    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .background(
                tint.gradient,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}

/// Riga di una sezione principale: tessera, nome, badge.
private struct SidebarNavRow: View {
    let section: AppSection
    let count: Int

    var body: some View {
        HStack(spacing: DS.s) {
            SidebarIconTile(systemImage: section.filledSystemImage, tint: section.tint)
            Text(section.label)
                .font(.dsMeta.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: DS.xs)
            // L'Inbox da smistare si nota: badge pieno nel suo colore.
            SidebarCountBadge(count: count, tint: section == .inbox ? section.tint : nil)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Contatore a capsula; nascosto a zero.
private struct SidebarCountBadge: View {
    let count: Int
    var tint: Color?

    var body: some View {
        if count > 0 {
            Text(count, format: .number)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint == nil ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
                                             : AnyShapeStyle(Color.white))
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 16)
                .background(
                    tint.map { AnyShapeStyle($0.gradient) }
                        ?? AnyShapeStyle(Color.primary.opacity(0.08)),
                    in: Capsule()
                )
                .contentTransition(.numericText(value: Double(count)))
                .animation(.dsQuick, value: count)
        }
    }
}

/// Intestazione di un gruppo: titolo e freccia riducono/espandono, azione
/// rapida a destra (su Mac appare al passaggio del mouse).
private struct SidebarGroupHeader: View {
    struct Accessory {
        let systemImage: String
        let help: String
        let action: () -> Void
    }

    let title: String
    var count = 0
    @Binding var isExpanded: Bool
    var accessory: Accessory?

    @State private var isHovering = false

    private var showsControls: Bool {
        #if os(macOS)
        isHovering || !isExpanded
        #else
        true
        #endif
    }

    var body: some View {
        HStack(spacing: DS.xs) {
            Button {
                withAnimation(.dsQuick) { isExpanded.toggle() }
            } label: {
                HStack(spacing: DS.xs) {
                    Text(title)
                    if !isExpanded && count > 0 {
                        Text("\(count)")
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(showsControls ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Espanso" : "Ridotto")
            .accessibilityHint("Riduci o espandi il gruppo")

            Spacer(minLength: 0)

            if let accessory {
                Button(action: accessory.action) {
                    Image(systemName: accessory.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(accessory.help)
                .accessibilityLabel(accessory.help)
                .opacity(showsControls ? 1 : 0)
            }
        }
        .onHover { hovering in
            withAnimation(.dsQuick) { isHovering = hovering }
        }
    }
}

/// Riga d'invito in un gruppo vuoto (non selezionabile).
private struct SidebarPlaceholderRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .frame(width: SidebarIconTile.size)
                Text(title)
                    .font(.dsMeta)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
