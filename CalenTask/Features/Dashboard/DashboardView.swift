import SwiftUI
import SwiftData
import Charts

/// La dashboard "Oggi" (D25): colpo d'occhio complessivo — urgenze in
/// dettaglio, agenda di oggi per priorità, salute dei progetti e timeline
/// dell'occupazione di progetti e fasi nel prossimo mese.
struct DashboardView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// All open (non-deleted, non-done) tasks; grouping happens in memory.
    @Query(filter: TodoTask.openPredicate, sort: \TodoTask.dueAt)
    private var allOpenTasks: [TodoTask]

    @Query(filter: TodoTask.inboxPredicate)
    private var allInboxTasks: [TodoTask]

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var allProjects: [Project]

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""

    private var configuration: AppConfiguration { .decode(configurationRaw) }

    private var openTasks: [TodoTask] {
        WorkspaceScope.filter(allOpenTasks, raw: scopeRaw, id: \.workspaceID)
            .filter { configuration.isEnabled(.activities) || $0.kind == .event }
    }

    private var inboxTasks: [TodoTask] {
        WorkspaceScope.filter(allInboxTasks, raw: scopeRaw, id: \.workspaceID)
    }

    private var projects: [Project] {
        WorkspaceScope.filter(allProjects, raw: scopeRaw, id: \.workspaceID)
    }

    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil },
           sort: \UserProfile.createdAt)
    private var people: [UserProfile]

    @Query(filter: #Predicate<Workspace> { $0.deletedAt == nil })
    private var allWorkspaces: [Workspace]

    /// Lo spazio condiviso (non personale) attivo, se lo scope ne ha scelto uno:
    /// è qui che le "richieste esterne" hanno senso (Intake spostato, v8).
    private var sharedScope: Workspace? {
        guard scopeRaw != "all", let id = UUID(uuidString: scopeRaw) else { return nil }
        return allWorkspaces.first { $0.id == id && !$0.isPersonal }
    }

    /// Bumped on scene activation so day-based grouping survives midnight.
    @State private var dayStamp = Date.now.startOfDay
    @State private var showsTeam = false
    @State private var showsCustomization = false

    /// Ogni persona vede il suo cruscotto (D35).
    @AppStorage("dashboardRole") private var roleRaw = DashboardRole.full.rawValue
    @State private var collaboratorID: UUID?

    // D93 — visibilità dei quattro indicatori in cima, ricordata per blocco.
    @AppStorage(StatBlock.overdue.storageKey) private var overdueVisRaw = StatBlock.overdue.defaultVisibility.rawValue
    @AppStorage(StatBlock.today.storageKey)   private var todayVisRaw   = StatBlock.today.defaultVisibility.rawValue
    @AppStorage(StatBlock.week.storageKey)    private var weekVisRaw    = StatBlock.week.defaultVisibility.rawValue
    @AppStorage(StatBlock.inbox.storageKey)   private var inboxVisRaw   = StatBlock.inbox.defaultVisibility.rawValue

    // D94 — ordine dei widget RICORDATO PER NUMERO DI COLONNE (1/2/3): se
    // riordino a 2 e torno a 3, ritrovo l'ordine di 3. I nascosti invece
    // sono condivisi. Le chiavi combaciano con DashboardLayout.orderKey(columns:).
    @AppStorage("dashboard.widgetOrder.1") private var order1Raw = ""
    @AppStorage("dashboard.widgetOrder.2") private var order2Raw = ""
    @AppStorage("dashboard.widgetOrder.3") private var order3Raw = ""
    @AppStorage(DashboardLayout.hiddenKey) private var widgetHiddenRaw = ""
    // Larghezza scelta per widget (una colonna / due / intera riga).
    @AppStorage(DashboardLayout.widthKey) private var widgetWidthRaw = ""

    private var role: DashboardRole {
        let saved = DashboardRole(rawValue: roleRaw) ?? .full
        return availableRoles.contains(saved) ? saved : .full
    }

    private var availableRoles: [DashboardRole] {
        guard configuration.isEnabled(.people), configuration.isEnabled(.activities)
        else { return [.full] }
        return DashboardRole.allCases.filter {
            $0 != .preproduction || configuration.isEnabled(.production)
        }
    }

    private var contentPadding: CGFloat {
        contentWidth < 600 ? DS.l : DS.xl
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.xl) {
                    dayOverview
                    if role != .full {
                        RoleDashboardView(
                            role: role,
                            openTasks: openTasks,
                            projects: projects,
                            people: people,
                            configuration: configuration,
                            collaboratorID: $collaboratorID
                        )
                        .onAppear {
                            if collaboratorID == nil { collaboratorID = people.first?.id }
                        }
                    } else {
                        if configuration.isEnabled(.dashboardMetrics) {
                            statTiles
                        }

                        widgetArea
                    }
                }
                .padding(contentPadding)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                contentWidth = width
            }
            .navigationTitle(role == .full ? greeting : role.label)
            .toolbar {
                // Scope e ingranaggio SOLO su iPhone: su iPad/Mac vivono
                // nella sidebar (e l'item .navigation copriva il toggle).
                #if os(iOS)
                if horizontalSizeClass == .compact {
                    ToolbarItem(placement: .navigation) {
                        WorkspaceScopePicker()
                    }
                    ToolbarItem {
                        Button {
                            router.isSettingsOpen = true
                        } label: {
                            Label("Impostazioni", systemImage: "gearshape")
                        }
                    }
                }
                #endif
                if availableRoles.count > 1 {
                    ToolbarItem(placement: .navigation) {
                        Menu {
                            Picker("Vista", selection: $roleRaw) {
                                ForEach(availableRoles) { role in
                                    Label(role.label, systemImage: role.systemImage)
                                        .tag(role.rawValue)
                                }
                            }
                        } label: {
                            Label(role.label, systemImage: role.systemImage)
                        }
                    }
                }
                // D93/D94 — personalizzazione di indicatori e widget.
                if role == .full {
                    ToolbarItem {
                        customizeButton
                    }
                }
                // F19 — gli aggiornamenti sulle attività, sempre a un click.
                if configuration.isEnabled(.people) {
                    ToolbarItem {
                        NotificationsBellButton()
                    }
                    ToolbarItem {
                        Button {
                            showsTeam = true
                        } label: {
                            Label("Team", systemImage: "person.2")
                        }
                    }
                }
                // L'Intake vive dove vivono le richieste: compare solo quando
                // stai guardando uno spazio condiviso (v8).
                if configuration.isEnabled(.externalRequests), let shared = sharedScope {
                    ToolbarItem {
                        Button {
                            router.isIntakeOpen = true
                        } label: {
                            Label("Nuova richiesta", systemImage: "envelope.arrow.triangle.branch")
                        }
                        .help("Registra una richiesta esterna in \(shared.name)")
                    }
                }
                ToolbarItem {
                    Button {
                        router.isQuickCaptureOpen = true
                    } label: {
                        Label("Nuova attività", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showsTeam) {
                TeamView()
            }
            .sheet(isPresented: $showsCustomization) {
                customizationSheet
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { dayStamp = Date.now.startOfDay }
        }
    }

    private var dayOverview: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DS.l) {
                dayHeading
                Spacer(minLength: DS.l)
                openCalendarButton
            }
            VStack(alignment: .leading, spacing: DS.m) {
                dayHeading
                openCalendarButton
            }
        }
    }

    private var dayHeading: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            Text(dayStamp, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.dsRowTitle.weight(.semibold))
            Text("La tua giornata, a colpo d’occhio.")
                .font(.dsCaption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var openCalendarButton: some View {
        Button {
            router.open(calendarDay: dayStamp)
        } label: {
            Label("Apri calendario", systemImage: "calendar")
        }
        .buttonStyle(.bordered)
        .fixedSize()
    }

    // MARK: Colonne della sala di controllo (D73)

    /// Larghezza viva del contenuto: decide quante colonne reggono.
    @State private var contentWidth: CGFloat = 0

    private var columnCount: Int {
        if contentWidth >= 1420 { 3 } else if contentWidth >= 820 { 2 } else { 1 }
    }

    /// F15 — i consigli per ottimizzare (widget "Suggerimenti").
    private var adviceSection: some View {
        DashboardAdviceSection(
            openTasks: openTasks,
            inboxCount: inboxTasks.count,
            projects: projects
        )
    }

    // MARK: Widget — stato persistito (D94)

    /// L'ordine grezzo per il numero di colonne CORRENTE: è la chiave del
    /// "ricordati l'ordine per layout" — 1, 2 e 3 colonne hanno il proprio.
    private var currentOrderRaw: String {
        switch columnCount {
        case 1: order1Raw
        case 2: order2Raw
        default: order3Raw
        }
    }

    private func setCurrentOrderRaw(_ value: String) {
        switch columnCount {
        case 1: order1Raw = value
        case 2: order2Raw = value
        default: order3Raw = value
        }
    }

    private var fullOrder: [DashboardWidget] {
        DashboardLayout.order(from: currentOrderRaw)
    }

    private var hiddenWidgets: Set<DashboardWidget> {
        DashboardLayout.hidden(from: widgetHiddenRaw)
    }

    private var visibleWidgets: [DashboardWidget] {
        fullOrder.filter { !excludedWidgets.contains($0) }
    }

    /// I moduli disattivati conservano le loro posizioni, proprio come i
    /// widget nascosti: riattivarli ripristina la personalizzazione.
    private var excludedWidgets: Set<DashboardWidget> {
        hiddenWidgets.union(DashboardWidget.allCases.filter { !$0.isAvailable(in: configuration) })
    }

    private var availableWidgets: [DashboardWidget] {
        fullOrder.filter { $0.isAvailable(in: configuration) }
    }

    private func setHidden(_ widget: DashboardWidget, _ hidden: Bool) {
        var set = hiddenWidgets
        if hidden { set.insert(widget) } else { set.remove(widget) }
        widgetHiddenRaw = DashboardLayout.encode(hidden: set)
    }

    private func widgetVisibleBinding(_ widget: DashboardWidget) -> Binding<Bool> {
        Binding(
            get: { !hiddenWidgets.contains(widget) },
            set: { setHidden(widget, !$0) }
        )
    }

    /// Salva il nuovo ordine dei visibili nel layout corrente, conservando
    /// la posizione dei nascosti.
    private func commitReorder(_ newVisibleOrder: [DashboardWidget]) {
        let merged = DashboardLayout.merged(
            full: fullOrder, visibleOrder: newVisibleOrder, hidden: excludedWidgets
        )
        setCurrentOrderRaw(DashboardLayout.encode(order: merged))
    }

    // Larghezza per widget (una colonna / due / intera riga).
    private var widgetWidths: [DashboardWidget: WidgetWidth] {
        DashboardLayout.widths(from: widgetWidthRaw)
    }

    private func widthOf(_ widget: DashboardWidget) -> WidgetWidth {
        widgetWidths[widget] ?? .single
    }

    private func widthBinding(_ widget: DashboardWidget) -> Binding<WidgetWidth> {
        Binding(
            get: { widthOf(widget) },
            set: { newValue in
                var widths = widgetWidths
                widths[widget] = newValue
                widgetWidthRaw = DashboardLayout.encode(widths: widths)
            }
        )
    }

    // MARK: Widget — griglia riordinabile (D94)

    /// Tutto ciò che sta sotto le tessere: griglia 1/2/3 colonne con
    /// drag&drop a reflow live. Click destro nello spazio (anche vuoto) o
    /// "Personalizza" per mostrare/nascondere.
    @ViewBuilder
    private var widgetArea: some View {
        Group {
            if visibleWidgets.isEmpty {
                emptyWidgetPlaceholder
            } else {
                ReorderableWidgetGrid(
                    items: visibleWidgets,
                    columns: columnCount,
                    spacing: DS.xl,
                    spanFor: { widthOf($0).span(columns: columnCount) },
                    content: { widgetContent($0) },
                    onReorder: { commitReorder($0) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu { widgetVisibilityMenuItems }
    }

    /// Il contenuto di ogni widget. Tutti rendono SEMPRE una card (con
    /// segnaposto quando sono a secco), così restano trascinabili.
    @ViewBuilder
    private func widgetContent(_ widget: DashboardWidget) -> some View {
        switch widget {
        case .urgent:
            if urgent.isEmpty {
                widgetPlaceholder(widget, message: "Nessuna urgenza. Puoi concentrarti sulla giornata.")
            } else {
                urgentSection
            }
        case .today:
            todayWidget
        case .upcoming:
            if upcoming.isEmpty {
                widgetPlaceholder(widget, message: "Niente in arrivo nei prossimi giorni.")
            } else {
                upcomingSection
            }
        case .advice:
            adviceSection
        case .trend:
            DashboardTrendSection()
        case .health:
            if projectHealth.isEmpty {
                widgetPlaceholder(widget, message: "Aggiungi attività ai progetti per vederne la salute.")
            } else {
                healthSection
            }
        case .timeline:
            if timelineBars.isEmpty {
                widgetPlaceholder(widget, message: "Nessuna fase pianificata nel prossimo mese.")
            } else {
                timelineSection
            }
        case .workload:
            workloadSection
        }
    }

    /// "Oggi": arretrati (non punitivi) + agenda del giorno, o lo stato
    /// "tutto sotto controllo" quando non c'è nulla.
    @ViewBuilder
    private var todayWidget: some View {
        if today.isEmpty && overdue.isEmpty {
            VStack(alignment: .leading, spacing: DS.s) {
                DSSectionHeader(title: "Oggi")
                DSEmptyState(
                    icon: "sparkles",
                    title: "Tutto sotto controllo",
                    subtitle: "Nessun impegno per oggi. Il calendario è pronto per i tuoi programmi.",
                    actionTitle: "Apri calendario",
                    action: { router.open(calendarDay: dayStamp) }
                )
                .frame(minHeight: 160)
            }
        } else if today.isEmpty {
            VStack(alignment: .leading, spacing: DS.s) {
                DSSectionHeader(title: "Oggi")
                overdueBanner
            }
        } else {
            VStack(alignment: .leading, spacing: DS.s) {
                if !overdue.isEmpty { overdueBanner }
                DashboardTaskWidget(title: "Oggi", tasks: today)
            }
        }
    }

    private func widgetPlaceholder(_ widget: DashboardWidget, message: String) -> some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: widget.title)
            Text(message)
                .font(.dsCaption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.l)
                .background(DSColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
    }

    private var emptyWidgetPlaceholder: some View {
        VStack(spacing: DS.s) {
            Image(systemName: "square.grid.2x2")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Nessun widget visibile")
                .font(.dsCaption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Scegli cosa tenere a portata di mano nella tua Home.")
                .font(.dsCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            customizeButton
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.xl)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.medium)
                .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }

    /// Voci per ogni widget — nel menu contestuale e in "Personalizza":
    /// mostra/nascondi + larghezza (una colonna / due / intera riga).
    @ViewBuilder
    private var widgetVisibilityMenuItems: some View {
        Section("Widget") {
            ForEach(availableWidgets) { widget in
                Menu {
                    Toggle(isOn: widgetVisibleBinding(widget)) {
                        Label("Mostra", systemImage: "eye")
                    }
                    Picker("Larghezza", selection: widthBinding(widget)) {
                        ForEach(WidgetWidth.allCases) { width in
                            Label(width.label, systemImage: width.icon).tag(width)
                        }
                    }
                } label: {
                    Label(widget.title, systemImage: widget.icon)
                }
            }
        }
        Button("Personalizza Home…") { showsCustomization = true }
    }

    /// S4: gli arretrati RESTANO in Oggi (non punitivo, Things)
    /// con il riprogramma in blocco a portata di mano.
    private var overdueBanner: some View {
        HStack {
            Label("\(overdue.count) in ritardo",
                  systemImage: "clock.arrow.circlepath")
                .font(.dsCaption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Riprogramma a oggi") {
                withAnimation(.dsSoft) {
                    for task in overdue {
                        task.dueAt = dayStamp
                        task.touch()
                    }
                }
            }
            .font(.dsCaption.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, DS.xs)
    }

    // MARK: Tiles (D93 — centrate e configurabili)

    /// Descrive un indicatore: cosa conta, come si colora, dove porta e
    /// con quale visibilità è stato impostato.
    private struct StatSpec: Identifiable {
        let block: StatBlock
        let count: Int
        let tint: Color
        let action: (() -> Void)?
        let visibility: Binding<BlockVisibility>
        var id: StatBlock { block }
    }

    /// I quattro blocchi con i loro conteggi e la binding di visibilità.
    private var statSpecs: [StatSpec] {
        [
            StatSpec(block: .overdue, count: overdue.count, tint: DSColor.overdue,
                     action: nil, visibility: visBinding($overdueVisRaw)),
            StatSpec(block: .today, count: today.count, tint: .accentColor,
                     action: nil, visibility: visBinding($todayVisRaw)),
            StatSpec(block: .week, count: thisWeek.count, tint: .accentColor,
                     action: { router.go(.calendar) }, visibility: visBinding($weekVisRaw)),
            StatSpec(block: .inbox, count: inboxTasks.count, tint: .accentColor,
                     action: { router.go(.inbox) }, visibility: visBinding($inboxVisRaw)),
        ]
    }

    private var visibleStatSpecs: [StatSpec] {
        statSpecs.filter { $0.visibility.wrappedValue.shouldShow(count: $0.count) }
    }

    /// Da raw String (@AppStorage) a `BlockVisibility` tipizzata.
    private func visBinding(_ raw: Binding<String>) -> Binding<BlockVisibility> {
        Binding(
            get: { BlockVisibility(rawValue: raw.wrappedValue) ?? .always },
            set: { raw.wrappedValue = $0.rawValue }
        )
    }

    /// Quante tessere stanno in fila: fino a 4 dove c'è spazio, 2 sul
    /// telefono. Mai schiacciate.
    private func statColumnCount(visible: Int) -> Int {
        #if os(iOS)
        if horizontalSizeClass == .compact { return min(visible, 2) }
        #endif
        return min(visible, 4)
    }

    /// G1/D93 — gli indicatori restano centrati nello spazio disponibile,
    /// senza stirarsi da bordo a bordo sugli schermi larghi.
    @ViewBuilder
    private var statTiles: some View {
        let specs = visibleStatSpecs
        if !specs.isEmpty {
            let cols = statColumnCount(visible: specs.count)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: DS.m), count: cols),
                spacing: DS.m
            ) {
                ForEach(specs) { spec in
                    StatTile(
                        title: spec.block.title, count: spec.count,
                        icon: spec.block.icon, tint: spec.tint, action: spec.action
                    )
                    .contextMenu { visibilityPicker(for: spec) }
                }
            }
            .frame(maxWidth: CGFloat(cols) * 210)
            .frame(maxWidth: .infinity)
        }
    }

    /// Il selettore dei tre stati, riusato nel menu contestuale di ogni
    /// tessera e nel menu "Personalizza".
    private func visibilityPicker(for spec: StatSpec) -> some View {
        Picker(spec.block.title, selection: spec.visibility) {
            ForEach(BlockVisibility.allCases) { mode in
                Label(mode.label, systemImage: mode.systemImage).tag(mode)
            }
        }
    }

    private var customizeButton: some View {
        Button {
            showsCustomization = true
        } label: {
            Label("Personalizza", systemImage: "slider.horizontal.3")
        }
        .accessibilityIdentifier("dashboard.customize")
    }

    /// Una superficie dedicata rende le scelte leggibili anche su iPhone.
    /// Il riordino ha pulsanti accessibili oltre al trascinamento nella Home.
    private var customizationSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Scegli i widget da mostrare e il loro ordine. La larghezza si adatta allo spazio disponibile.")
                        .foregroundStyle(.secondary)
                }
                ForEach(availableWidgets) { widget in
                    Section {
                        Toggle(isOn: widgetVisibleBinding(widget)) {
                            Label(widget.title, systemImage: widget.icon)
                        }
                        if !hiddenWidgets.contains(widget) {
                            Picker("Larghezza", selection: widthBinding(widget)) {
                                ForEach(WidgetWidth.allCases) { width in
                                    Text(width.label).tag(width)
                                }
                            }
                        }
                        HStack {
                            Text("Posizione")
                            Spacer()
                            Button {
                                moveWidget(widget, offset: -1)
                            } label: {
                                Label("Sposta su", systemImage: "arrow.up")
                            }
                            .labelStyle(.iconOnly)
                            .disabled(availableWidgets.first == widget)
                            .accessibilityLabel("Sposta \(widget.title) su")
                            Button {
                                moveWidget(widget, offset: 1)
                            } label: {
                                Label("Sposta giù", systemImage: "arrow.down")
                            }
                            .labelStyle(.iconOnly)
                            .disabled(availableWidgets.last == widget)
                            .accessibilityLabel("Sposta \(widget.title) giù")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if configuration.isEnabled(.dashboardMetrics) {
                    Section("Indicatori") {
                        ForEach(statSpecs) { spec in
                            visibilityPicker(for: spec)
                        }
                    }
                }
                Section {
                    Text("Attiva altri moduli nelle Impostazioni per aggiungere widget. Disattivare un modulo conserva le tue preferenze.")
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Personalizza Home")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { showsCustomization = false }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 480, idealHeight: 640)
        #endif
    }

    private func moveWidget(_ widget: DashboardWidget, offset: Int) {
        let available = availableWidgets
        guard let index = available.firstIndex(of: widget),
              available.indices.contains(index + offset) else { return }
        let reordered = DashboardLayout.reordering(available, moving: widget, to: available[index + offset])
        let unavailable = Set(DashboardWidget.allCases.filter { !$0.isAvailable(in: configuration) })
        let merged = DashboardLayout.merged(full: fullOrder, visibleOrder: reordered, hidden: unavailable)
        setCurrentOrderRaw(DashboardLayout.encode(order: merged))
    }

    // MARK: Urgenti (D25 — in evidenza, dettagliati)

    private var urgentSection: some View {
        DashboardTaskWidget(title: "Urgenti", tasks: urgent, tint: DSColor.priority(.urgent), previewCount: 3)
    }

    // MARK: In arrivo

    private var upcomingSection: some View {
        DashboardTaskWidget(title: "In arrivo", tasks: upcoming, previewCount: 4)
    }

    // MARK: Salute progetti (D25)

    private struct HealthSlice: Identifiable {
        let id = UUID()
        let project: String
        let colorHex: String
        let label: String   // "Completate" | "Aperte" | "In ritardo"
        let count: Int
    }

    private var projectHealth: [HealthSlice] {
        projects.flatMap { project -> [HealthSlice] in
            let live = project.tasks.filter { $0.deletedAt == nil && !$0.isPhase && !$0.isTemplate }
            guard !live.isEmpty else { return [] }
            let done = live.filter(\.isDone).count
            let late = live.filter(\.isOverdue).count
            let open = live.count - done - late
            return [
                HealthSlice(project: project.name, colorHex: project.colorHex,
                            label: "Completate", count: done),
                HealthSlice(project: project.name, colorHex: project.colorHex,
                            label: "Aperte", count: max(0, open)),
                HealthSlice(project: project.name, colorHex: project.colorHex,
                            label: "In ritardo", count: late),
            ]
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Salute progetti", count: projects.count)
            Chart(projectHealth) { slice in
                BarMark(
                    x: .value("Attività", slice.count),
                    y: .value("Progetto", slice.project)
                )
                .foregroundStyle(by: .value("Stato", slice.label))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale([
                "Completate": DSColor.status(.done),
                "Aperte": Color.accentColor.opacity(0.55),
                "In ritardo": DSColor.overdue,
            ])
            .chartLegend(position: .bottom, spacing: DS.s)
            .frame(height: max(120, CGFloat(projects.count) * 44))
            .padding(DS.l)
            .background(DSColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
    }

    // MARK: Timeline progetti — prossimo mese (D25)

    private struct TimelineBar: Identifiable {
        let id = UUID()
        let project: String
        let phase: String
        let colorHex: String
        let start: Date
        let end: Date
    }

    private var timelineWindow: ClosedRange<Date> {
        let calendar = Calendar.app
        return dayStamp...calendar.date(byAdding: .day, value: 30, to: dayStamp)!
    }

    private var timelineBars: [TimelineBar] {
        let window = timelineWindow
        return projects.flatMap { project -> [TimelineBar] in
            project.phaseTasks.compactMap { phase in
                let children = phase.liveSubtasks.filter { !$0.isTemplate }
                let spans: [(Date, Date)] = children.compactMap { task in
                    let start = task.startAt ?? task.dueAt
                    let end = task.endAt ?? task.dueAt ?? task.startAt
                    guard let start, let end else { return nil }
                    return (min(start, end), max(start, end))
                }
                guard var start = spans.map(\.0).min(),
                      var end = spans.map(\.1).max(),
                      start <= window.upperBound, end >= window.lowerBound
                else { return nil }
                start = max(start, window.lowerBound)
                end = min(end, window.upperBound)
                return TimelineBar(
                    project: project.name, phase: phase.title,
                    colorHex: project.colorHex, start: start, end: end
                )
            }
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Prossimi 30 giorni", count: timelineBars.count)
            Chart(timelineBars) { bar in
                BarMark(
                    xStart: .value("Inizio", bar.start),
                    xEnd: .value("Fine", bar.end),
                    y: .value("Progetto", "\(bar.project) · \(bar.phase)"),
                    height: .fixed(10)
                )
                .foregroundStyle(Color(hex: bar.colorHex).gradient)
                .cornerRadius(5)

                RuleMark(x: .value("Oggi", dayStamp))
                    .foregroundStyle(DSColor.overdue.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartXScale(domain: timelineWindow.lowerBound...timelineWindow.upperBound)
            .chartLegend(.hidden)
            .frame(height: max(120, CGFloat(timelineBars.count) * 34))
            .padding(DS.l)
            .background(DSColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
    }

    // MARK: Workload / capacity (D34)

    private struct LoadSlice: Identifiable {
        let id = UUID()
        let person: String
        let bucket: String
        let count: Int
    }

    private static let loadBuckets = ["In ritardo", "Questa settimana", "Più avanti", "Senza data"]

    private var workloadSlices: [LoadSlice] {
        let calendar = Calendar.app
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: dayStamp) ?? dayStamp

        func bucket(for task: TodoTask) -> String {
            guard let dueAt = task.dueAt else { return "Senza data" }
            if dueAt < dayStamp { return "In ritardo" }
            if dueAt < weekEnd { return "Questa settimana" }
            return "Più avanti"
        }

        var names = people.map { ($0.id as UUID?, $0.name) }
        names.append((nil, "Non assegnate"))

        return names.flatMap { id, name -> [LoadSlice] in
            let mine = openTasks.filter { $0.assigneeID == id }
            guard !mine.isEmpty || id != nil else { return [] }
            return Self.loadBuckets.compactMap { label in
                let count = mine.filter { bucket(for: $0) == label }.count
                return count > 0 ? LoadSlice(person: name, bucket: label, count: count) : nil
            }
        }
    }

    private var workloadSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Carico di lavoro", count: openTasks.count)
            if workloadSlices.isEmpty {
                Text("Assegna le attività alle persone del team per vedere il carico.")
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
                    .padding(DS.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DSColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            } else {
                Chart(workloadSlices) { slice in
                    BarMark(
                        x: .value("Attività", slice.count),
                        y: .value("Persona", slice.person)
                    )
                    .foregroundStyle(by: .value("Quando", slice.bucket))
                    .cornerRadius(3)
                }
                .chartForegroundStyleScale([
                    "In ritardo": DSColor.overdue,
                    "Questa settimana": Color.accentColor,
                    "Più avanti": Color.accentColor.opacity(0.45),
                    "Senza data": Color.secondary.opacity(0.35),
                ])
                .chartLegend(position: .bottom, spacing: DS.s)
                .frame(height: max(110, CGFloat(Set(workloadSlices.map(\.person)).count) * 44))
                .padding(DS.l)
                .background(DSColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            }
        }
    }

    // MARK: Grouping

    private var urgent: [TodoTask] {
        openTasks
            .filter { $0.priority == .urgent }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var overdue: [TodoTask] {
        openTasks.filter { task in
            guard let dueAt = task.dueAt else { return false }
            return dueAt < dayStamp && task.priority != .urgent
        }
    }

    /// Oggi, ordinata per priorità poi per orario (D25). S4: dentro ci stanno
    /// anche il "quando" arrivato (startAt ≤ oggi, stile Things) e gli
    /// arretrati — che NON vengono nascosti in una sezione punitiva.
    private var today: [TodoTask] {
        let calendar = Calendar.app
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: dayStamp)
        else { return [] }
        return openTasks
            .filter { task in
                guard task.priority != .urgent else { return false }
                let dates = [task.startAt, task.dueAt, task.remindAt].compactMap(\.self)
                if dates.contains(where: { calendar.isDate($0, inSameDayAs: dayStamp) }) {
                    return true
                }
                // Il "quando" è arrivato (solo task/promemoria: gli eventi passati
                // non rientrano in Oggi).
                if let startAt = task.startAt,
                   task.kind == .task || task.kind == .reminder,
                   startAt < endOfToday {
                    return true
                }
                // Arretrato: resta in Oggi, niente lista della vergogna.
                if let dueAt = task.dueAt, dueAt < dayStamp { return true }
                return false
            }
            .sorted {
                ($1.priorityRaw, agendaDate($0)) < ($0.priorityRaw, agendaDate($1))
            }
    }

    private var thisWeek: [TodoTask] {
        let calendar = Calendar.app
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: dayStamp) else { return [] }
        return openTasks.filter { task in
            let dates = [task.startAt, task.dueAt, task.remindAt].compactMap(\.self)
            return dates.contains { $0 >= dayStamp && $0 < weekEnd }
        }
    }

    /// Cose future: prossimi elementi datati dopo oggi.
    private var upcoming: [TodoTask] {
        let calendar = Calendar.app
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayStamp) else { return [] }
        return openTasks
            .filter { task in
                let date = task.startAt ?? task.dueAt ?? task.remindAt
                guard let date else { return false }
                return date >= tomorrow
            }
            .sorted { agendaDate($0) < agendaDate($1) }
    }

    private func agendaDate(_ task: TodoTask) -> Date {
        task.startAt ?? task.remindAt ?? task.dueAt ?? .distantFuture
    }

    private var greeting: String {
        let hour = Calendar.app.component(.hour, from: .now)
        switch hour {
        case 5..<13: return "Buongiorno"
        case 13..<18: return "Buon pomeriggio"
        default: return "Buonasera"
        }
    }

}

#Preview {
    DashboardView()
        .environment(AppRouter())
        .modelContainer(PreviewSampleData.make().container)
}
