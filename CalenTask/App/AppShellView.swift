import SwiftUI
import SwiftData
import Combine
import CoreData

/// La shell adattiva (D70): UNA grammatica di navigazione, tre tagli.
/// Width regular (Mac + iPad) → split view con la sidebar ricca;
/// width compact (iPhone, iPad in split) → tab + "Sfoglia".
struct AppShellView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    private var configuration: AppConfiguration { .decode(configurationRaw) }
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.undoManager) private var undoManager
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// First-run (S7/D68): il benvenuto si mostra UNA volta.
    @AppStorage("didShowWelcome") private var didShowWelcome = false
    @State private var showsWelcome = false
    /// Cosa sta nella finestra (colonna attività, pannello Oggi): misurato
    /// QUI, sulla finestra intera, e applicato fuori dal layout — vedi
    /// `updateWidthClass`.
    @State private var widthClass = ShellWidthClass()
    @State private var safeModeDismissed = false

    var body: some View {
        @Bindable var router = router
        Group {
            #if os(macOS)
            ShellSplitView(widthClass: widthClass)
            #else
            if horizontalSizeClass == .regular {
                ShellSplitView(widthClass: widthClass)
                    .overlay(alignment: .bottomTrailing) {
                        captureFloatingButton(bottomPadding: DS.l)
                    }
            } else {
                ShellTabView()
                    .overlay(alignment: .bottomTrailing) {
                        captureFloatingButton(bottomPadding: 64)
                    }
            }
            #endif
        }
        #if os(macOS)
        // F18 — su Mac la cattura è un pannello flottante: si chiude
        // cliccando fuori o con Esc (le sheet macOS non lo permettono).
        .overlay {
            if router.isQuickCaptureOpen {
                captureOverlay
            }
        }
        // Spazio intermedio: il dettaglio come popup modale, allo STESSO
        // livello della cattura. Un .overlay sulla NavigationSplitView verrebbe
        // ritagliato dalla split view nativa e non si vedrebbe.
        .overlay {
            if showTaskPopup, let taskID = router.taskForInspector {
                taskPopupOverlay(taskID: taskID)
            }
        }
        .animation(.dsQuick, value: router.isQuickCaptureOpen)
        .animation(.dsQuick, value: showTaskPopup)
        .overlay(alignment: .bottom) {
            if LaunchGuard.isSafeMode && !safeModeDismissed {
                safeModeBanner
            }
        }
        #else
        .sheet(isPresented: $router.isQuickCaptureOpen) {
            captureSheet
        }
        #endif
        // La finestra intera, non la split view: la sua larghezza non cambia
        // quando l'inspector entra o esce.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            updateWidthClass(width)
        }
        .sheet(isPresented: $router.isCommandPaletteOpen) {
            CommandPaletteView()
        }
        .sheet(isPresented: $router.isIntakeOpen) {
            IntakeFormView()
        }
        .sheet(isPresented: $showsWelcome) {
            WelcomeView()
        }
        #if os(iOS)
        .sheet(isPresented: $router.isSettingsOpen) {
            SettingsView()
        }
        #endif
        #if os(macOS)
        // F14/F31 — su Mac il deep link apre l'inspector, non una sheet.
        .onChange(of: router.taskToOpen) { _, taskID in
            guard let taskID else { return }
            router.taskForInspector = taskID
            router.taskToOpen = nil
        }
        .onAppear {
            // Tap su notifica a freddo: il valore è già lì prima di onChange.
            if let taskID = router.taskToOpen {
                router.taskForInspector = taskID
                router.taskToOpen = nil
            }
        }
        #else
        .sheet(item: deepLinkBinding) { ref in
            TaskDeepLinkView(taskID: ref.id)
        }
        #endif
        .task {
            do {
                try SeedService.ensureSeed(in: modelContext)
            } catch {
                reportFailure("Seed failed: \(error)")
            }
            WidgetBridge.refresh(in: modelContext)
            WeatherService.shared.refreshIfNeeded()
            if !didShowWelcome {
                didShowWelcome = true
                showsWelcome = true
            }
            // Arrivata a regime: il prossimo avvio non sarà "sicuro".
            try? await Task.sleep(for: .seconds(20))
            LaunchGuard.markLaunchCompleted()
        }
        .onChange(of: configurationRaw) { _, _ in
            // A module can disappear while its page is open. Return to a
            // stable destination without changing any underlying record.
            switch router.destination {
            case .section(let section):
                if !configuration.navigationSections.contains(section) { router.go(.calendar) }
            case .project:
                if !configuration.isEnabled(.projects) { router.go(.calendar) }
            case .smartList:
                if !configuration.isEnabled(.smartLists) { router.go(.calendar) }
            case .tag:
                if !configuration.isEnabled(.tags) { router.go(.calendar) }
            }
        }
        // #22 — ⌘Z / ⇧⌘Z (e "scuoti per annullare" su iPhone) sulle modifiche
        // ai dati: il contesto SwiftData usa l'undo manager della finestra.
        .onAppear { modelContext.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in modelContext.undoManager = manager }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Leaving the foreground is the moment to hand the widget
            // a fresh snapshot of today — and to riprogrammare il digest (D67).
            if phase == .background || phase == .inactive {
                WidgetBridge.refresh(in: modelContext)
                scheduleDigest()
            }
            // #4 — all'avvio e a ogni ritorno in primo piano: riallinea le
            // notifiche (anche delle attività arrivate da iCloud).
            if phase == .active {
                NotificationService.shared.resyncAll(in: modelContext)
            }
        }
        // #29 — modifiche arrivate da iCloud mentre l'app è aperta: notifiche,
        // digest e widget si riallineano subito (prima solo all'avvio e al
        // ritorno in primo piano). A raffica finita: una sync ne manda tante.
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSPersistentStoreRemoteChange)
                .debounce(for: .seconds(2), scheduler: RunLoop.main)
        ) { _ in
            guard scenePhase == .active else { return }
            NotificationService.shared.resyncAll(in: modelContext)
            scheduleDigest()
            WidgetBridge.refresh(in: modelContext)
        }
    }

    private struct TaskRef: Identifiable {
        let id: UUID
    }

    /// Bridges router.taskToOpen (set by notification taps) to a sheet item.
    private var deepLinkBinding: Binding<TaskRef?> {
        Binding(
            get: { router.taskToOpen.map(TaskRef.init) },
            set: { router.taskToOpen = $0?.id }
        )
    }

    /// Crash 0.0.3 (EXC_BREAKPOINT in `_postWindowNeedsUpdateConstraints`):
    /// l'inspector entrava/usciva DENTRO il passaggio di layout (es. mentre
    /// si ridimensiona o si ingrandisce la finestra); NSSplitView rifaceva i
    /// vincoli a ripetizione finché AppKit sollevava "more Update Constraints
    /// in Window passes than there are views in the window". Ora la decisione
    /// si applica al giro successivo del run loop, con isteresi.
    private func updateWidthClass(_ width: CGFloat) {
        guard widthClass.resolved(for: width) != widthClass else { return }
        Task { @MainActor in
            let next = widthClass.resolved(for: width)
            if next != widthClass { widthClass = next }
        }
    }

    /// D67 — i numeri del digest si calcolano sul giorno in cui suonerà (8:00).
    private func scheduleDigest() {
        let calendar = Calendar.current
        var fireDay = calendar.startOfDay(for: .now)
        if let eight = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: .now),
           eight <= .now,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: fireDay) {
            fireDay = tomorrow
        }
        let all = (try? modelContext.fetch(
            FetchDescriptor<TodoTask>(predicate: TodoTask.openPredicate)
        )) ?? []
        let events = all.filter {
            ($0.kind == .event || $0.kind == .shootDay)
                && $0.startAt.map { calendar.isDate($0, inSameDayAs: fireDay) } == true
        }.count
        let deadlines = all.filter {
            $0.dueAt.map { calendar.isDate($0, inSameDayAs: fireDay) } == true
        }.count
        let overdue = all.filter { ($0.dueAt ?? .distantFuture) < fireDay }.count
        NotificationService.shared.scheduleDailyDigest(
            events: events, deadlines: deadlines, overdue: overdue
        )
    }

    #if os(macOS)
    /// F18 — pannello flottante: backdrop cliccabile + carta centrata in alto.
    private var captureOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { router.isQuickCaptureOpen = false }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Cattura rapida")
                        .font(.dsSectionTitle)
                    Spacer()
                    Button {
                        router.isQuickCaptureOpen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chiudi")
                }
                .padding([.horizontal, .top], DS.l)
                QuickCaptureView()
            }
            .frame(width: 460)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.large)
                    .strokeBorder(DSColor.hairline)
            }
            .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
            .padding(.top, 96)
            .onExitCommand { router.isQuickCaptureOpen = false }
        }
        .transition(.opacity)
    }

    /// C'è un'attività da aprire ma manca lo spazio per la colonna destra
    /// (o siamo in avvio sicuro, che la colonna non la usa).
    private var showTaskPopup: Bool {
        widthClass.isMeasured && (!widthClass.fitsTaskInspector || LaunchGuard.isSafeMode)
            && router.taskForInspector != nil
    }

    /// Avviso dell'avvio sicuro, in basso: dice cosa è successo e cosa manca.
    private var safeModeBanner: some View {
        HStack(spacing: DS.m) {
            Image(systemName: "stethoscope")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Avvio sicuro")
                    .font(.dsMeta.weight(.semibold))
                Text("L'ultimo avvio si è interrotto: finestra ripristinata, pannello destro e mini-calendario spenti per questa sessione. Al prossimo avvio tutto torna normale.")
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Ok") { withAnimation(.dsQuick) { safeModeDismissed = true } }
        }
        .padding(DS.m)
        .frame(maxWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.large))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.large)
                .strokeBorder(DSColor.hairline)
        }
        .padding(DS.l)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// macOS: popup modale centrato con sfondo cliccabile (clic fuori → chiude)
    /// ed Esc. Le modifiche sono già salvate live, quindi chiude e basta.
    @ViewBuilder
    private func taskPopupOverlay(taskID: UUID) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { router.taskForInspector = nil }
            TaskInspectorView(taskID: taskID) {
                router.taskForInspector = nil
            }
            .frame(width: 480, height: 640)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.large))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.large))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.large)
                    .strokeBorder(DSColor.hairline)
            }
            .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
            .onExitCommand { router.taskForInspector = nil }
        }
        .transition(.opacity)
    }
    #else
    private var captureSheet: some View {
        QuickCaptureView()
            .presentationDetents([.height(230)])
            .presentationDragIndicator(.visible)
    }
    #endif

    #if os(iOS)
    /// E12 — FAB di cattura in Liquid Glass tinto: vetro SOLO nel chrome.
    private func captureFloatingButton(bottomPadding: CGFloat) -> some View {
        Button {
            router.isQuickCaptureOpen = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
        }
        .glassEffect(.regular.tint(Color.accentColor).interactive(), in: Circle())
        .padding(.trailing, DS.l)
        .padding(.bottom, bottomPadding)
        .accessibilityLabel("Nuova attività")
    }
    #endif
}

// MARK: - Regular: split view (Mac + iPad, D70)

/// Cosa sta nella finestra: la colonna dettaglio attività (F14) e il
/// pannello Oggi (D74). Con isteresi: una colonna appare a soglia piena e
/// sparisce solo `hysteresis` punti più sotto, così la sua comparsa (che su
/// macOS può allargare la finestra) non la rimette subito in discussione.
struct ShellWidthClass: Equatable {
    var isMeasured = false
    var fitsTaskInspector = false
    var fitsTodayPanel = false

    static let hysteresis: CGFloat = 48

    func resolved(for width: CGFloat) -> ShellWidthClass {
        guard width > 0, width.isFinite else { return self }
        func fits(_ threshold: CGFloat, isShown: Bool) -> Bool {
            width >= (isMeasured && isShown ? threshold - Self.hysteresis : threshold)
        }
        return ShellWidthClass(
            isMeasured: true,
            fitsTaskInspector: fits(TaskPanel.inspectorMinWidth, isShown: fitsTaskInspector),
            fitsTodayPanel: fits(TodayPanel.minimumShellWidth, isShown: fitsTodayPanel)
        )
    }
}

/// Sidebar ricca + detail. La destinazione del router È il detail.
private struct ShellSplitView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    private var configuration: AppConfiguration { .decode(configurationRaw) }

    /// Misurata da `AppShellView` sulla finestra intera (mai qui: la split
    /// view cambia quando l'inspector entra).
    let widthClass: ShellWidthClass

    /// D74 — pannello Oggi: scelta dell'utente (menu Vista / X su macOS)…
    @AppStorage(TodayPanel.storageKey) private var wantsTodayPanel = true

    /// …ma appare solo se la finestra ha davvero spazio (27"/32").
    private var canShowTodayPanel: Bool {
        configuration.isEnabled(.todayInspector) && widthClass.fitsTodayPanel
            && !LaunchGuard.isSafeMode
    }

    /// Largo abbastanza da reggere il dettaglio come colonna destra. Sotto
    /// questa soglia (ma ancora regular) l'attività si apre in un popup.
    private var canShowTaskInspector: Bool {
        widthClass.fitsTaskInspector && !LaunchGuard.isSafeMode
    }

    /// L'attività è da mostrare nell'inspector (c'è e c'è spazio).
    private var taskInInspector: Bool {
        router.taskForInspector != nil && canShowTaskInspector
    }

    /// Un solo slot inspector: il dettaglio attività (F14) ha precedenza
    /// quando c'è spazio, poi il pannello Oggi (D74).
    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: {
                taskInInspector || (wantsTodayPanel && canShowTodayPanel)
            },
            set: { isOpen in
                guard !isOpen else { return }
                if taskInInspector {
                    router.taskForInspector = nil
                } else {
                    wantsTodayPanel = false
                }
            }
        )
    }

    /// Spazio intermedio (regular ma stretto): l'attività si apre in un popup
    /// modale, che non comprime il contenuto come farebbe la colonna destra.
    private var taskSheetBinding: Binding<Bool> {
        Binding(
            get: {
                router.taskForInspector != nil && widthClass.isMeasured && !canShowTaskInspector
            },
            set: { isOpen in
                if !isOpen { router.taskForInspector = nil }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            detailView
                // E8 rimosso (F13): backgroundExtensionEffect specchia il
                // contenuto sotto toolbar/sidebar e crea "fantasmi" di testo
                // sulle liste — va bene per immagini hero, non per testo.
                .inspector(isPresented: inspectorBinding) {
                    Group {
                        if let taskID = router.taskForInspector, canShowTaskInspector {
                            TaskInspectorView(taskID: taskID) {
                                router.taskForInspector = nil
                            }
                        } else if wantsTodayPanel && canShowTodayPanel {
                            TodayPanelView(onClose: closeAction)
                        } else {
                            // Niente "Oggi" durante la chiusura del dettaglio:
                            // evita il lampo del pannello mentre la colonna
                            // collassa (il task è già nil, ma Today non è
                            // l'occupante voluto qui).
                            Color.clear
                        }
                    }
                    .inspectorColumnWidth(min: 260, ideal: 340, max: 460)
                }
                #if os(iOS)
                // iPad regular stretto: popup come sheet (già dismissibile
                // toccando fuori o trascinando).
                .sheet(isPresented: taskSheetBinding) {
                    if let taskID = router.taskForInspector {
                        taskPopup(taskID: taskID)
                    }
                }
                #endif
        }
        #if os(macOS)
        .frame(minWidth: 840, minHeight: 560)
        #endif
    }

    /// Su macOS si può riaprire dal menu Vista (⌥⌘0), quindi la X ha senso;
    /// su iPad il pannello segue solo lo spazio disponibile.
    private var closeAction: (() -> Void)? {
        #if os(macOS)
        { wantsTodayPanel = false }
        #else
        nil
        #endif
    }

    #if os(iOS)
    /// iPad regular stretto: il dettaglio come sheet ampia.
    @ViewBuilder
    private func taskPopup(taskID: UUID) -> some View {
        TaskInspectorView(taskID: taskID) {
            router.taskForInspector = nil
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    #endif

    @ViewBuilder
    private var detailView: some View {
        switch router.destination {
        case .section(let section):
            sectionView(section)
        case .project(let id):
            NavigationStack {
                ProjectDestinationView(projectID: id)
            }
        case .smartList(let id):
            NavigationStack {
                SmartListDestinationView(listID: id)
            }
        case .tag(let id):
            NavigationStack {
                TagDestinationView(tagID: id)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .quick:
            QuickModeView()
        case .dashboard:
            DashboardView()
        case .inbox:
            InboxView()
        case .calendar:
            CalendarScreen()
        case .projects:
            ProjectListView()
        case .people:
            NavigationStack {
                PeopleView()
            }
        }
    }
}

// MARK: - Compact: tab + Sfoglia (iPhone, D70)

private struct ShellTabView: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    private var configuration: AppConfiguration { .decode(configurationRaw) }

    @Query(filter: TodoTask.inboxPredicate)
    private var inboxTasks: [TodoTask]

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    private var scopedInboxCount: Int {
        WorkspaceScope.filter(inboxTasks, raw: scopeRaw, id: \.workspaceID).count
    }

    /// Lo stack di Sfoglia: le destinazioni programmatiche (palette, sidebar
    /// di un altro device, deep link) atterrano qui come push.
    @State private var browsePath: [AppDestination] = []

    private enum CompactTab: Hashable {
        case dashboard, inbox, calendar, browse
    }

    /// La tab è una PROIEZIONE della destinazione del router: progetti,
    /// liste e persone vivono dentro Sfoglia.
    private var tabSelection: Binding<CompactTab> {
        Binding(
            get: {
                switch router.destination {
                case .section(.quick): .browse
                case .section(.dashboard): .dashboard
                case .section(.inbox): .inbox
                case .section(.calendar): .calendar
                case .section(.projects), .section(.people),
                     .project, .smartList, .tag: .browse
                }
            },
            set: { tab in
                switch tab {
                case .dashboard: router.go(.dashboard)
                case .inbox: router.go(.inbox)
                case .calendar: router.go(.calendar)
                case .browse:
                    // Ri-tap sulla tab già attiva = torna alla radice.
                    if tabSelection.wrappedValue == .browse {
                        browsePath = []
                        router.go(.projects)
                    } else if !destinationLivesInBrowse {
                        router.go(.projects)
                    }
                }
            }
        )
    }

    private var destinationLivesInBrowse: Bool {
        switch router.destination {
        case .section(.quick), .section(.projects), .section(.people), .project, .smartList, .tag: true
        default: false
        }
    }

    var body: some View {
        TabView(selection: tabSelection) {
            CalendarScreen()
                .tabItem { tabLabel(.calendar) }
                .tag(CompactTab.calendar)
            DashboardView()
                .tabItem { tabLabel(.dashboard) }
                .tag(CompactTab.dashboard)
            if configuration.isEnabled(.activities) {
                InboxView()
                    .tabItem { tabLabel(.inbox) }
                    .tag(CompactTab.inbox)
                    .badge(scopedInboxCount)
            }
            BrowseView(path: $browsePath)
                .tabItem { Label("Sfoglia", systemImage: "square.grid.2x2") }
                .tag(CompactTab.browse)
        }
        #if os(iOS)
        // E8 — la tab bar si ritira quando scorri: contenuto al centro.
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .onChange(of: router.destination) { _, destination in
            syncBrowsePath(with: destination)
        }
        .onAppear {
            syncBrowsePath(with: router.destination)
        }
    }

    private func tabLabel(_ section: AppSection) -> some View {
        Label(section.label, systemImage: section.systemImage)
    }

    private func syncBrowsePath(with destination: AppDestination) {
        switch destination {
        case .project, .smartList, .tag, .section(.people), .section(.quick):
            browsePath = [destination]
        case .section(.projects):
            browsePath = []
        default:
            break
        }
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return AppShellView()
        .environment(AppRouter())
        .modelContainer(preview.container)
}
