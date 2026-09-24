import SwiftUI
import SwiftData

/// Il calendario (D42): cinque viste — Giorno, Settimana, Mese, Trimestre
/// (per pianificare anche le tasse) e Anno — con sync ai calendari di
/// sistema (D10) e time-blocking (D14).
enum CalendarViewMode: String, CaseIterable, Identifiable {
    case day, week, month, quarter, year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: "Giorno"
        case .week: "Settimana"
        case .month: "Mese"
        case .quarter: "Trimestre"
        case .year: "Anno"
        }
    }

    var systemImage: String {
        switch self {
        case .day: "calendar.day.timeline.left"
        case .week: "calendar.day.timeline.leading"
        case .month: "calendar"
        case .quarter: "calendar.badge.clock"
        case .year: "calendar.circle"
        }
    }
}

struct CalendarScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var selectedDay = Date.now.startOfDay
    @State private var showsCapture = false
    @State private var calendarSync = CalendarSyncService.shared
    @State private var isSyncing = false
    // S5 — trova slot libero (rule-based).
    @State private var slotProposals: [Date] = []
    @State private var slotDuration = 60
    @State private var showsSlotResults = false
    /// Pinch in corso sulla griglia del Giorno: altezza-ora di partenza.
    /// Pinch verticale in corso: altezza-ora di partenza + valore "vivo".
    /// Il valore vivo si committa su disco solo a fine gesto (niente scritture
    /// a ogni frame → pinch fluido).
    @State private var pinchStartHeight: CGFloat?
    @State private var liveHourHeight: CGFloat?
    /// Indice del calendario (D per-render → cache, fix lag navigazione):
    /// ricostruito SOLO quando le task cambiano davvero, non a ogni
    /// ridisegno di `body` — che durante il pinch verticale succede a ogni
    /// frame (`liveHourHeight` è uno `@State` di questa stessa view).
    /// Prima veniva ricostruito da zero a ogni frame anche per un pinch che
    /// non tocca affatto quali task esistono.
    @State private var calendarIndex = CalendarTaskIndex(tasks: [], calendar: Calendar.app)

    @AppStorage("calendarViewMode") private var modeRaw = CalendarViewMode.month.rawValue
    /// Day sub-mode: agenda · griglia (time-blocking, D14).
    @AppStorage("calendarDayMode") private var dayModeRaw = "agenda"
    /// Densità della griglia/Gantt del giorno: altezza di un'ora (pinch-zoom).
    @AppStorage("calendarHourHeight") private var hourHeightStored = 56.0
    /// E10 — heatmap densità nel mese (in Anno è sempre attiva).
    @AppStorage("calendarMonthHeatmap") private var monthHeatmap = false
    /// S5 — vista N-giorni (la "settimana" può essere 2–9 giorni).
    @AppStorage("calendarWeekDayCount") private var weekDayCount = 7
    /// F30 — il trimestre si può togliere dalla barra delle viste.
    @AppStorage("calendarShowsQuarter") private var showsQuarter = true
    /// F28 — nascondere le attività senza progetto (per guardare SOLO un progetto).
    @AppStorage("calendarHidesUnassigned") private var hidesUnassigned = false
    /// S5 — calendar set: progetti nascosti dal calendario (CSV di UUID).
    @AppStorage("calendarHiddenProjects") private var hiddenProjectsRaw = ""
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    @AppStorage("weatherEnabled") private var weatherEnabled = true

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.sortOrder)
    private var allProjects: [Project]

    /// All live tasks; windows are filtered in memory (current scale).
    @Query(filter: #Predicate<TodoTask> { $0.deletedAt == nil && !$0.isTemplate })
    private var allTasks: [TodoTask]

    /// I membri dello spazio: risolvono `assigneeID` per le corsie "per persona".
    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil })
    private var people: [UserProfile]

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"

    private var tasks: [TodoTask] {
        WorkspaceScope.filter(allTasks, raw: scopeRaw, id: \.workspaceID)
    }

    private let calendar = Calendar.app

    private var mode: CalendarViewMode {
        let saved = CalendarViewMode(rawValue: modeRaw) ?? .month
        return availableModes.contains(saved) ? saved : .month
    }

    private var configuration: AppConfiguration { .decode(configurationRaw) }
    private var showsAdvancedViews: Bool { configuration.isEnabled(.calendarAdvancedViews) }
    private var showsSummary: Bool { configuration.isEnabled(.calendarSummary) }
    private var showsWeather: Bool { weatherEnabled && configuration.isEnabled(.calendarWeather) }
    private var visibleWeekDayCount: Int {
        showsAdvancedViews && [2, 3, 5, 7, 9].contains(weekDayCount) ? weekDayCount : 7
    }
    private var visibleWeekStart: Date {
        visibleWeekDayCount == 7 ? weekStart : selectedDay.startOfDay
    }

    /// Intervallo della densità oraria (altezza di un'ora).
    private let hourHeightRange: ClosedRange<CGFloat> = 28...160

    /// Altezza di un'ora: durante il pinch vince il valore "vivo".
    private var hourHeight: CGFloat { liveHourHeight ?? CGFloat(hourHeightStored) }

    /// Vero quando il Giorno mostra la griglia oraria: lì il pinch regola la
    /// densità, altrove cambia scala.
    private var isDayGridLike: Bool {
        mode == .day && dayModeRaw == "grid"
    }

    /// Pinch verticale: nella Griglia comprime/allarga le ore (densità), nelle
    /// altre viste cambia scala. Cross-platform (trackpad su Mac, pinch su iOS).
    private var densityOrScalePinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard isDayGridLike else { return }
                let base = pinchStartHeight ?? hourHeight
                if pinchStartHeight == nil { pinchStartHeight = base }
                liveHourHeight = (base * value.magnification).clamped(to: hourHeightRange)
            }
            .onEnded { value in
                if isDayGridLike {
                    if let live = liveHourHeight { hourHeightStored = Double(live) }
                    liveHourHeight = nil
                    pinchStartHeight = nil
                } else if value.magnification > 1.2 {
                    zoomScale(toDetail: true)
                } else if value.magnification < 0.83 {
                    zoomScale(toDetail: false)
                }
            }
    }

    /// Comprime/allarga la densità (pulsanti −/+ e tasti, alternativa al pinch).
    private func adjustHourHeight(_ delta: CGFloat) {
        withAnimation(.dsSoft) {
            hourHeightStored = Double((CGFloat(hourHeightStored) + delta)
                .clamped(to: hourHeightRange))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlBar

                // E7 — zoom semantico tra le scale: il cambio vista è un
                // passaggio di livello, non uno swap secco.
                Group {
                    switch mode {
                    case .day:
                        dayContent(calendarIndex)
                    case .week:
                        weekContent(calendarIndex)
                    case .month:
                        monthContent(calendarIndex)
                    case .quarter:
                        quarterContent(calendarIndex)
                    case .year:
                        yearContent(calendarIndex)
                    }
                }
                .id(mode)
                .transition(.scale(scale: 0.97).combined(with: .opacity))
                .simultaneousGesture(densityOrScalePinch)
            }
            .background(DSColor.surfaceSecondary)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("Calendario")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .principal) { modeSegmented }
                #else
                ToolbarItem(placement: .principal) {
                    if horizontalSizeClass == .regular {
                        modeSegmented
                    } else {
                        modeMenu
                    }
                }
                #endif
                ToolbarItem { addButton }
                ToolbarItem { calendarSetMenu }
            }
            .sheet(isPresented: $showsCapture) {
                captureSheet
            }
            .sheet(isPresented: $showsSlotResults) {
                slotResultsSheet
            }
            #if os(macOS)
            // S5 — keyboard-first: 1-5 viste, T oggi, frecce per navigare.
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in
                handleKeyPress(press)
            }
            #endif
            .task {
                if calendarSync.isSyncEnabled {
                    await runSync()
                }
            }
            // F2 — il mini-mese in sidebar atterra su un giorno preciso.
            .onAppear {
                consumeDeepLinkDay()
                // F30 — modalità salvata non più disponibile: si torna al mese.
                normalizeSavedMode()
            }
            .onChange(of: availableModes) { _, _ in normalizeSavedMode() }
            .onChange(of: router.calendarDayToOpen) { _, _ in
                consumeDeepLinkDay()
            }
            // Ricostruisce l'indice solo quando le task cambiano DAVVERO
            // (ogni mutazione passa per `touch()`, che aggiorna `updatedAt` —
            // vedi CLAUDE.md), non a ogni ridisegno di `body` innescato da
            // pinch/densità/selezione giorno/hover.
            .onChange(of: liveTasks.map(\.updatedAt), initial: true) { _, _ in
                calendarIndex = CalendarTaskIndex(tasks: liveTasks, calendar: calendar)
            }
        }
    }

    private func consumeDeepLinkDay() {
        guard let day = router.calendarDayToOpen else { return }
        selectedDay = day.startOfDay
        router.calendarDayToOpen = nil
    }

    private func normalizeSavedMode() {
        if !availableModes.contains(where: { $0.rawValue == modeRaw }) {
            modeRaw = CalendarViewMode.month.rawValue
        }
    }

    // MARK: Barra di controllo (vista + navigazione)

    /// F30 — le viste disponibili rispettano la scelta sul trimestre.
    private var availableModes: [CalendarViewMode] {
        [.day, .week, .month] + (showsAdvancedViews ? (showsQuarter ? [.quarter, .year] : [.year]) : [])
    }

    private var controlBar: some View {
        VStack(spacing: DS.s) {
            HStack {
                Text(periodTitle)
                    .font(.dsSectionTitle)
                    .id(periodTitle)
                    .transition(.opacity)
                Spacer()
                if mode == .week, showsAdvancedViews {
                    // S5 — la "settimana" è elastica: 2–9 giorni.
                    Menu {
                        ForEach([2, 3, 5, 7, 9], id: \.self) { count in
                            Button {
                                withAnimation(.dsQuick) { weekDayCount = count }
                            } label: {
                                if count == weekDayCount {
                                    Label("\(count) giorni", systemImage: "checkmark")
                                } else {
                                    Text("\(count) giorni")
                                }
                            }
                        }
                    } label: {
                        Text("\(weekDayCount) gg")
                            .font(.dsCaption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(.trailing, DS.s)
                }
                if mode == .month, showsSummary {
                    // E10 — toggle heatmap densità (Timepage).
                    Button {
                        withAnimation(.dsQuick) { monthHeatmap.toggle() }
                    } label: {
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.dsMeta)
                            .foregroundStyle(monthHeatmap ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Heatmap densità")
                    .padding(.trailing, DS.s)
                }
                periodNavigator
            }
        }
        .padding(.horizontal, DS.l)
        .padding(.vertical, DS.s)
    }

    /// Switch rapido tra le viste: segmented in toolbar (Mac + iPad regular),
    /// stile Calendar di sistema. Su iPhone si riduce a `modeMenu`.
    private var modeSegmented: some View {
        Picker("Vista", selection: $modeRaw.animation(.dsQuick)) {
            ForEach(availableModes) { mode in
                Text(mode.label).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    /// Selettore vista compatto (iPhone): menu con icone.
    private var modeMenu: some View {
        Menu {
            Picker("Vista", selection: $modeRaw.animation(.dsQuick)) {
                ForEach(availableModes) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode.rawValue)
                }
            }
        } label: {
            Label(mode.label, systemImage: mode.systemImage)
        }
    }

    /// "+" in toolbar: nuova attività ancorata al giorno selezionato.
    private var addButton: some View {
        Button {
            showsCapture = true
        } label: {
            Label("Nuova attività", systemImage: "plus")
        }
        .help("Nuova attività in questo giorno")
    }

    /// ‹ Oggi › in un unico controllo a capsula: naviga e torna a oggi.
    private var periodNavigator: some View {
        HStack(spacing: 0) {
            navButton("chevron.left") { shift(-1) }
            Button {
                selectedDay = .now.startOfDay
            } label: {
                Text("Oggi")
                    .font(.dsCaption.weight(.semibold))
                    .padding(.horizontal, DS.s)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            navButton("chevron.right") { shift(1) }
        }
        .foregroundStyle(Color.accentColor)
        .frame(height: 28)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
    }

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.dsCaption.weight(.bold))
                .padding(.horizontal, DS.s)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var periodTitle: String {
        switch mode {
        case .day:
            return selectedDay.appFormatted(.dateTime.weekday(.wide).day().month(.wide))
        case .week:
            let start = visibleWeekStart
            let end = calendar.date(byAdding: .day, value: visibleWeekDayCount - 1, to: start) ?? start
            return "\(start.appFormatted(.dateTime.day().month(.abbreviated))) – \(end.appFormatted(.dateTime.day().month(.abbreviated)))"
        case .month:
            return selectedDay.appFormatted(.dateTime.month(.wide).year())
        case .quarter:
            let quarter = (calendar.component(.month, from: selectedDay) - 1) / 3 + 1
            return "T\(quarter) \(calendar.component(.year, from: selectedDay).formatted(.number.grouping(.never)))"
        case .year:
            return calendar.component(.year, from: selectedDay).formatted(.number.grouping(.never))
        }
    }

    /// E7 — pinch su iOS: scala semantica giorno↔settimana↔mese↔trimestre↔anno.
    private func zoomScale(toDetail: Bool) {
        let order = Array(availableModes.reversed())
        guard let index = order.firstIndex(of: mode) else { return }
        let next = toDetail ? index + 1 : index - 1
        guard order.indices.contains(next) else { return }
        withAnimation(.dsSoft) { modeRaw = order[next].rawValue }
    }

    private func shift(_ delta: Int) {
        let component: Calendar.Component
        let value: Int
        switch mode {
        case .day: (component, value) = (.day, delta)
        case .week: (component, value) = (.day, delta * visibleWeekDayCount)
        case .month: (component, value) = (.month, delta)
        case .quarter: (component, value) = (.month, delta * 3)
        case .year: (component, value) = (.year, delta)
        }
        // Changing period replaces event data. A screen-wide spring made
        // unrelated blocks interpolate between the old and new day's times.
        selectedDay = calendar.date(byAdding: component, value: value, to: selectedDay) ?? selectedDay
    }

    private var weekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start ?? selectedDay.startOfDay
    }

    // MARK: Giorno — l'hub organizzativo della giornata

    /// Testata + fascia "tutto il giorno" **fisse**, sotto solo la griglia/Gantt
    /// (o l'agenda) **scorre**. Il pinch ne regola la densità oraria.
    private func dayContent(_ data: CalendarTaskIndex) -> some View {
        VStack(spacing: 0) {
            dayHubHeader(data)
                .padding(.horizontal, DS.l)
                .padding(.top, DS.m)
                .padding(.bottom, DS.s)

            // Fascia "Tutto il giorno": fissa sopra la griglia che scorre.
            if isDayGridLike, !data.allDayTasks(on: selectedDay).isEmpty {
                AllDayLaneView(tasks: data.allDayTasks(on: selectedDay))
                    .padding(.horizontal, DS.l)
                    .padding(.bottom, DS.s)
            }

            if isDayGridLike {
                Divider()
            }

            dayScrollingBody(data)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// La parte fissa: colpo d'occhio (relativo · riepilogo · meteo) + selettore
    /// sotto-modalità, le corsie del Gantt e il controllo densità.
    private func dayHubHeader(_ data: CalendarTaskIndex) -> some View {
        VStack(alignment: .leading, spacing: DS.m) {
            if showsSummary || showsWeather {
                DayHeaderView(day: selectedDay, tasks: data.tasks(on: selectedDay),
                              showsSummary: showsSummary, showsWeather: showsWeather)
            }
            HStack(spacing: DS.m) {
                DayModeToggle(selection: $dayModeRaw)
                Spacer(minLength: 0)
                if isDayGridLike {
                    densityControl
                }
            }
            if configuration.isEnabled(.calendarUnscheduled), !data.unscheduled.isEmpty {
                DisclosureGroup("Da pianificare · \(data.unscheduled.count)") {
                    ScrollView(.horizontal) {
                        HStack(spacing: DS.s) {
                            ForEach(data.unscheduled, id: \.id) { task in
                                TaskOpenLink(task: task) {
                                    Text(task.title)
                                        .font(.dsCaption)
                                        .lineLimit(1)
                                        .padding(DS.s)
                                        .background(.quaternary, in: Capsule())
                                }
                                .draggable(task.id.uuidString)
                            }
                        }
                    }
                }
                .font(.dsCaption)
            }
        }
    }

    @ViewBuilder
    private func dayScrollingBody(_ data: CalendarTaskIndex) -> some View {
        switch dayModeRaw {
        case "grid":
            DayTimelineView(
                day: selectedDay,
                plannedTasks: data.timedTasks(on: selectedDay),
                hourHeight: hourHeight,
                people: people
            )
            .padding([.horizontal, .bottom], DS.l)
            .padding(.top, DS.s)
        default:
            ScrollView {
                DayAgendaView(day: selectedDay, tasks: data.tasks(on: selectedDay))
                    .padding(DS.l)
            }
        }
    }

    /// Comprimi/allarga le ore (− / +): l'equivalente del pinch dove non c'è.
    private var densityControl: some View {
        HStack(spacing: 0) {
            Button { adjustHourHeight(-10) } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .disabled(CGFloat(hourHeightStored) <= hourHeightRange.lowerBound)
            Divider().frame(height: 14)
            Button { adjustHourHeight(10) } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .disabled(CGFloat(hourHeightStored) >= hourHeightRange.upperBound)
        }
        .font(.dsCaption.weight(.bold))
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
        .help("Comprimi o allarga le ore")
    }

    /// Dettaglio del giorno selezionato sotto la griglia del Mese: titolo,
    /// colpo d'occhio e agenda (qui basta l'agenda, il time-blocking vive nel
    /// Giorno).
    private func monthDayDetail(_ data: CalendarTaskIndex) -> some View {
        VStack(alignment: .leading, spacing: DS.m) {
            Text(selectedDay.appFormatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.dsSectionTitle)
            if showsSummary || showsWeather {
                DayHeaderView(day: selectedDay, tasks: data.tasks(on: selectedDay),
                              showsSummary: showsSummary, showsWeather: showsWeather)
            }
            DayAgendaView(day: selectedDay, tasks: data.tasks(on: selectedDay))
        }
    }

    // MARK: Settimana

    private func weekContent(_ data: CalendarTaskIndex) -> some View {
        WeekGridView(
            // 7 giorni = settimana ancorata al lunedì; N giorni = dal selezionato.
            weekStart: visibleWeekStart,
            dayCount: visibleWeekDayCount,
            data: data,
            people: people,
            showsWeather: showsWeather
        ) { day in
            withAnimation(.dsQuick) {
                selectedDay = day.startOfDay
                modeRaw = CalendarViewMode.day.rawValue
            }
        }
        .padding([.horizontal, .bottom], DS.l)
    }

    // MARK: Mese

    private func monthContent(_ data: CalendarTaskIndex) -> some View {
        ScrollView {
            VStack(spacing: DS.xl) {
                MonthGridView(
                    month: CalendarMath.startOfMonth(for: selectedDay, calendar: calendar),
                    selectedDay: $selectedDay,
                    tasksByDay: data.tasksByDay,
                    showsHeatmap: showsSummary && monthHeatmap,
                    showsEventChips: showsRichMonth
                )

                monthDayDetail(data)
            }
            .padding(DS.l)
        }
    }

    /// F24 — celle ricche dove lo spazio c'è: Mac sempre, iPad regular.
    private var showsRichMonth: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    // MARK: Trimestre — la vista per pianificare (anche le tasse, D42)

    private var quarterMonths: [Date] {
        let quarterIndex = (calendar.component(.month, from: selectedDay) - 1) / 3
        let year = calendar.component(.year, from: selectedDay)
        return (0..<3).compactMap { offset in
            calendar.date(from: DateComponents(year: year, month: quarterIndex * 3 + 1 + offset))
        }
    }

    /// F26 — il trimestre come tre colonne di pianificazione a lungo termine:
    /// per ogni mese il mini-calendario, le fasi di progetto attive e le
    /// scadenze. Tutto il mese in una colonna, tutto il trimestre in un colpo.
    private func quarterContent(_ data: CalendarTaskIndex) -> some View {
        ScrollView {
            #if os(macOS)
            HStack(alignment: .top, spacing: DS.l) {
                ForEach(quarterMonths, id: \.self) { month in
                    quarterMonthColumn(month, data: data)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(DS.l)
            #else
            VStack(spacing: DS.l) {
                ForEach(quarterMonths, id: \.self) { month in
                    quarterMonthColumn(month, data: data)
                }
            }
            .padding(DS.l)
            #endif
        }
    }

    private func quarterMonthColumn(_ month: Date, data: CalendarTaskIndex) -> some View {
        let monthDeadlines = deadlines(inMonth: month, data: data)
        let monthPhases = phases(inMonth: month)
        return VStack(alignment: .leading, spacing: DS.m) {
            miniMonth(month, data: data)

            if !monthPhases.isEmpty {
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text("Fasi attive")
                        .font(.dsCaption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(monthPhases, id: \.id) { phase in
                        TaskOpenLink(task: phase) {
                            HStack(spacing: DS.xs) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(phase.project.map { Color(hex: $0.colorHex) }
                                          ?? .accentColor)
                                    .frame(width: 3, height: 14)
                                Text(phase.title)
                                    .font(.dsCaption.weight(.medium))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if let project = phase.project {
                                    Text(project.name)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
            }

            if !monthDeadlines.isEmpty {
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text("Scadenze · \(monthDeadlines.count)")
                        .font(.dsCaption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(monthDeadlines.prefix(8), id: \.id) { task in
                            quarterDeadlineRow(task)
                        }
                        if monthDeadlines.count > 8 {
                            Text("+\(monthDeadlines.count - 8) altre")
                                .font(.dsCaption)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, DS.xs)
                        }
                    }
                }
            } else {
                Text("Nessuna scadenza")
                    .font(.dsCaption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.m)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.medium)
                .strokeBorder(DSColor.hairline)
        }
    }

    private func quarterDeadlineRow(_ task: TodoTask) -> some View {
        HStack(spacing: DS.s) {
            DSCheckToggle(isDone: task.isDone, font: .body) {
                withAnimation(.dsSoft) { task.toggleDone() }
            }
            TaskOpenLink(task: task) {
                HStack(spacing: DS.s) {
                    Text(task.title)
                        .font(.dsCaption.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let dueAt = task.dueAt {
                        Text(dueAt.appFormatted(.dateTime.day().month(.abbreviated)))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(task.isOverdue
                                ? AnyShapeStyle(DSColor.overdue)
                                : AnyShapeStyle(.tertiary))
                    }
                }
                .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 3)
        .taskContextMenu(task)
    }

    /// Le fasi di progetto che toccano questo mese (inizio..scadenza).
    private func phases(inMonth month: Date) -> [TodoTask] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        return tasks.filter { task in
            guard task.isPhase, !task.isDone else { return false }
            guard let anchor = task.startAt ?? task.dueAt else { return false }
            let start = task.startAt ?? anchor
            let end = task.dueAt ?? task.endAt ?? start
            return start < interval.end && end >= interval.start
        }
        .sorted { ($0.startAt ?? .distantFuture) < ($1.startAt ?? .distantFuture) }
    }

    // MARK: Anno

    private func yearContent(_ data: CalendarTaskIndex) -> some View {
        ScrollView {
            VStack(spacing: DS.l) {
                // F27 — l'anno racconta i numeri prima dei quadri.
                if showsSummary { yearSummary(data) }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: DS.l), count: yearColumns),
                    spacing: DS.l
                ) {
                    ForEach(yearMonths, id: \.self) { month in
                        yearMonthCard(month, data: data)
                    }
                }
            }
            .padding(DS.l)
        }
    }

    /// F27 — riepilogo dell'anno: totali + istogramma del carico per mese.
    private func yearSummary(_ data: CalendarTaskIndex) -> some View {
        let counts = yearMonths.map { data.count(inMonth: $0) }
        let maxCount = max(counts.max() ?? 1, 1)
        let yearTasks = data.tasks.filter { task in
            let anchor = task.startAt ?? task.dueAt
            return anchor.map {
                calendar.component(.year, from: $0)
                    == calendar.component(.year, from: selectedDay)
            } == true
        }
        let events = yearTasks.filter { $0.kind == .event || $0.kind == .shootDay }.count
        let deadlines = yearTasks.filter { $0.dueAt != nil && $0.kind != .event }.count
        let done = yearTasks.filter(\.isDone).count

        return HStack(alignment: .center, spacing: DS.xl) {
            HStack(spacing: DS.xl) {
                yearStat(value: events, label: "Eventi", tint: .blue)
                yearStat(value: deadlines, label: "Scadenze", tint: .orange)
                yearStat(value: done, label: "Fatte", tint: DSColor.status(.done))
            }

            Spacer(minLength: DS.l)

            // Istogramma: un tap sul mese ci porta dentro.
            HStack(alignment: .bottom, spacing: DS.xs) {
                ForEach(Array(yearMonths.enumerated()), id: \.offset) { index, month in
                    Button {
                        withAnimation(.dsSoft) {
                            selectedDay = month
                            modeRaw = CalendarViewMode.month.rawValue
                        }
                    } label: {
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(CalendarMath.isSameMonth(month, .now, calendar: calendar)
                                      ? Color.accentColor
                                      : Color.accentColor.opacity(0.35))
                                .frame(width: 16,
                                       height: max(3, CGFloat(counts[index]) / CGFloat(maxCount) * 40))
                            Text(month.appFormatted(.dateTime.month(.narrow)))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(DS.l)
        .dsSurface(.card)
    }

    private func yearStat(value: Int, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.dsNumeric.weight(.bold))
                .font(.title3)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(.dsCaption)
                .foregroundStyle(.secondary)
        }
    }

    /// Card mese per la vista Anno: titolo con conteggio, heatmap densità,
    /// superficie elevata — l'anno come 12 quadri, non come una tabella.
    private func yearMonthCard(_ month: Date, data: CalendarTaskIndex) -> some View {
        let count = data.count(inMonth: month)
        let isCurrent = CalendarMath.isSameMonth(month, .now, calendar: calendar)
        return VStack(alignment: .leading, spacing: DS.s) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    withAnimation(.dsSoft) {
                        selectedDay = month
                        modeRaw = CalendarViewMode.month.rawValue
                    }
                } label: {
                    Text(month.appFormatted(.dateTime.month(.wide)))
                        .font(.dsMeta.weight(.semibold))
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.dsNumeric)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            MiniMonthView(
                month: month,
                selectedDay: selectedDay,
                countsByDay: data.countsByDay,
                showsTitle: false,
                showsHeatmap: true,
                onSelectDay: { day in
                    withAnimation(.dsSoft) {
                        selectedDay = day.startOfDay
                        modeRaw = CalendarViewMode.day.rawValue
                    }
                }
            )
        }
        .padding(DS.m)
        .dsSurface(.card)
        .dsHoverHighlight(cornerRadius: DS.Radius.medium)
    }

    private var yearColumns: Int {
        #if os(macOS)
        4
        #else
        2
        #endif
    }

    private var yearMonths: [Date] {
        let year = calendar.component(.year, from: selectedDay)
        return (1...12).compactMap { calendar.date(from: DateComponents(year: year, month: $0)) }
    }

    private func miniMonth(_ month: Date, data: CalendarTaskIndex, heatmap: Bool = false) -> some View {
        MiniMonthView(
            month: month,
            selectedDay: selectedDay,
            countsByDay: data.countsByDay,
            showsHeatmap: heatmap,
            onSelectDay: { day in
                withAnimation(.dsQuick) {
                    selectedDay = day.startOfDay
                    modeRaw = CalendarViewMode.day.rawValue
                }
            },
            onSelectMonth: { month in
                withAnimation(.dsQuick) {
                    selectedDay = month
                    modeRaw = CalendarViewMode.month.rawValue
                }
            }
        )
    }

    // MARK: Calendar set (S5) — progetti accesi/spenti a un tap

    private var calendarSetMenu: some View {
        Menu {
            // F28 — scorciatoie di scope: tutto / solo personale / un progetto.
            Section("Mostra") {
                Button {
                    withAnimation(.dsQuick) {
                        hiddenProjectsRaw = ""
                        hidesUnassigned = false
                    }
                } label: {
                    Label("Tutto", systemImage: "square.grid.2x2")
                }
                Button {
                    withAnimation(.dsQuick) {
                        hiddenProjectsRaw = allProjects
                            .map(\.id.uuidString).sorted().joined(separator: ",")
                        hidesUnassigned = false
                    }
                } label: {
                    Label("Solo personale (senza progetto)", systemImage: "person")
                }
                Menu {
                    ForEach(allProjects, id: \.id) { project in
                        Button(project.name) {
                            withAnimation(.dsQuick) {
                                hiddenProjectsRaw = allProjects
                                    .filter { $0.id != project.id }
                                    .map(\.id.uuidString).sorted().joined(separator: ",")
                                hidesUnassigned = true
                            }
                        }
                    }
                } label: {
                    Label("Solo un progetto", systemImage: "folder")
                }
            }
            Section("Progetti") {
                ForEach(allProjects, id: \.id) { project in
                    Toggle(isOn: visibilityBinding(for: project)) {
                        Label(project.name, systemImage: "circle.fill")
                    }
                }
                Toggle(isOn: unassignedBinding) {
                    Label("Senza progetto", systemImage: "tray")
                }
            }
            // F29/F30 — strumenti raccolti qui: una toolbar più pulita.
            Section("Strumenti") {
                if showsSummary {
                    Menu {
                        Button("30 minuti") { findSlots(duration: 30) }
                        Button("1 ora") { findSlots(duration: 60) }
                        Button("2 ore") { findSlots(duration: 120) }
                    } label: {
                        Label("Trova slot libero", systemImage: "wand.and.stars")
                    }
                }
                if showsAdvancedViews {
                    Toggle(isOn: quarterVisibilityBinding) {
                        Label("Vista Trimestre", systemImage: "calendar.badge.clock")
                    }
                }
            }
        } label: {
            Label("Calendari",
                  systemImage: hiddenProjectIDs.isEmpty && !hidesUnassigned
                      ? "checklist.checked" : "checklist")
        }
        .help("Scegli cosa vedere in calendario")
    }

    private var unassignedBinding: Binding<Bool> {
        Binding(
            get: { !hidesUnassigned },
            set: { visible in
                withAnimation(.dsQuick) { hidesUnassigned = !visible }
            }
        )
    }

    private var quarterVisibilityBinding: Binding<Bool> {
        Binding(
            get: { showsQuarter },
            set: { newValue in
                withAnimation(.dsQuick) {
                    showsQuarter = newValue
                    if !newValue, mode == .quarter {
                        modeRaw = CalendarViewMode.month.rawValue
                    }
                }
            }
        )
    }

    private func visibilityBinding(for project: Project) -> Binding<Bool> {
        Binding(
            get: { !hiddenProjectIDs.contains(project.id.uuidString) },
            set: { visible in
                var hidden = hiddenProjectIDs
                if visible {
                    hidden.remove(project.id.uuidString)
                } else {
                    hidden.insert(project.id.uuidString)
                }
                withAnimation(.dsQuick) {
                    hiddenProjectsRaw = hidden.sorted().joined(separator: ",")
                }
            }
        )
    }

    // MARK: Trova slot libero (S5) — rule-based, primi 3 buchi
    // (F29: vive nel menu Calendari, non più in toolbar.)

    private func findSlots(duration: Int) {
        slotDuration = duration
        slotProposals = Self.freeSlots(
            duration: duration, in: liveTasks, calendar: calendar
        )
        showsSlotResults = true
    }

    /// I primi 3 inizi liberi (ore lavorative 8–20, prossimi 7 giorni),
    /// considerando occupato tutto ciò che ha startAt/endAt.
    static func freeSlots(
        duration: Int, in tasks: [TodoTask],
        calendar: Calendar, now: Date = .now, maxResults: Int = 3
    ) -> [Date] {
        var results: [Date] = []
        let busy: [(Date, Date)] = tasks.compactMap { task in
            guard let start = task.startAt, !task.allDay, !task.isDone else { return nil }
            return (start, task.endAt ?? start.addingTimeInterval(3600))
        }
        for offset in 0..<7 {
            guard results.count < maxResults,
                  let day = calendar.date(byAdding: .day, value: offset,
                                          to: calendar.startOfDay(for: now)),
                  let windowStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day),
                  let windowEnd = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day)
            else { continue }

            var cursor = max(windowStart, offset == 0 ? Self.roundUp(now, calendar) : windowStart)
            let dayBusy = busy
                .filter { $0.1 > windowStart && $0.0 < windowEnd }
                .sorted { $0.0 < $1.0 }
            for (busyStart, busyEnd) in dayBusy {
                if busyStart.timeIntervalSince(cursor) >= TimeInterval(duration * 60),
                   results.count < maxResults {
                    results.append(cursor)
                }
                cursor = max(cursor, busyEnd)
            }
            if results.count < maxResults,
               windowEnd.timeIntervalSince(cursor) >= TimeInterval(duration * 60) {
                results.append(cursor)
            }
        }
        return Array(results.prefix(maxResults))
    }

    /// Arrotonda al quarto d'ora successivo.
    private static func roundUp(_ date: Date, _ calendar: Calendar) -> Date {
        let minute = calendar.component(.minute, from: date)
        let delta = (15 - minute % 15) % 15
        return calendar.date(byAdding: .minute, value: delta, to: date) ?? date
    }

    private var slotResultsSheet: some View {
        NavigationStack {
            List {
                if slotProposals.isEmpty {
                    Text("Nessun buco libero nei prossimi 7 giorni (ore 8–20).")
                        .font(.dsMeta)
                        .foregroundStyle(.secondary)
                } else {
                    Section("Primi slot liberi · \(slotDuration) min") {
                        ForEach(slotProposals, id: \.self) { slot in
                            Button {
                                createBlock(at: slot)
                            } label: {
                                HStack {
                                    Text(slot.appFormatted(
                                        .dateTime.weekday(.wide).day().month().hour().minute()
                                    ))
                                    .font(.dsMeta.weight(.medium))
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Trova slot")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { showsSlotResults = false }
                }
            }
        }
        #if os(macOS)
        .frame(width: 380, height: 300)
        #endif
    }

    private func createBlock(at slot: Date) {
        do {
            let (workspace, me) = try SeedService.ensureSeed(in: modelContext)
            let event = TodoTask(
                workspaceID: workspace.id,
                title: "Nuovo evento",
                kind: .event,
                startAt: slot,
                endAt: slot.addingTimeInterval(TimeInterval(slotDuration * 60)),
                createdByID: me.id
            )
            modelContext.insert(event)
            try modelContext.save()
            showsSlotResults = false
            selectedDay = slot.startOfDay
            router.open(taskID: event.id)   // dettaglio subito, per dargli un nome
        } catch {
            assertionFailure("Slot creation failed: \(error)")
        }
    }

    #if os(macOS)
    // MARK: Scorciatoie (S5): 1-5 viste, T oggi, ← → navigazione

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .leftArrow: shift(-1); return .handled
        case .rightArrow: shift(1); return .handled
        default: break
        }
        let order = availableModes
        switch press.characters {
        case "1", "2", "3", "4", "5":
            if let index = Int(press.characters), order.indices.contains(index - 1) {
                withAnimation(.dsSoft) { modeRaw = order[index - 1].rawValue }
                return .handled
            }
            return .ignored
        case "t", "T":
            selectedDay = .now.startOfDay
            return .handled
        case "+", "=":
            guard isDayGridLike else { return .ignored }
            adjustHourHeight(10)
            return .handled
        case "-", "_":
            guard isDayGridLike else { return .ignored }
            adjustHourHeight(-10)
            return .handled
        default:
            return .ignored
        }
    }
    #endif

    // MARK: System-calendar sync (D10)
    //
    // Nessun tasto "Sincronizza ora" (rimosso 2026-09-10, anacronistico: un
    // pulsante manuale non serve quando la sync gira già da sola). Resta
    // solo l'automatico: all'apertura del Calendario (sotto) e a ogni
    // modifica di una task (`touch()` → `CalendarSyncService.pushIfNeeded`).
    // L'interruttore on/off e l'ultimo esito vivono in Impostazioni →
    // Sincronizzazione (`SettingsView.syncSections`), non nel calendario.

    private func runSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let (workspace, me) = try SeedService.ensureSeed(in: modelContext)
            await calendarSync.syncNow(
                in: modelContext, workspaceID: workspace.id, createdBy: me.id
            )
        } catch {
            assertionFailure("Sync seed failed: \(error)")
        }
    }

    // MARK: Capture

    @ViewBuilder
    private var captureSheet: some View {
        let prefill = selectedDay
        #if os(macOS)
        VStack(alignment: .leading, spacing: 0) {
            Text("Nuova attività · \(prefill.dsRelativeLabel)")
                .font(.dsSectionTitle)
                .padding(.horizontal, DS.l)
                .padding(.top, DS.l)
            QuickCaptureView(initialDueDate: prefill)
        }
        .frame(width: 420)
        #else
        QuickCaptureView(initialDueDate: prefill)
            .presentationDetents([.height(230)])
            .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: Data slices

    private var hiddenProjectIDs: Set<String> {
        Set(hiddenProjectsRaw.split(separator: ",").map(String.init))
    }

    private var liveTasks: [TodoTask] {
        let hiddenIDs = hiddenProjectIDs
        return tasks.filter { task in
            guard !task.isPhase else { return false }
            // S5 calendar set: i progetti spenti spariscono dal calendario.
            if let project = task.project,
               hiddenIDs.contains(project.id.uuidString) {
                return false
            }
            // F28 — focus su un progetto: via le attività senza progetto.
            if hidesUnassigned, task.project == nil {
                return false
            }
            return true
        }
    }

    private func deadlines(inMonth month: Date, data: CalendarTaskIndex) -> [TodoTask] {
        data.tasks
            .filter { task in
                guard !task.isDone, let dueAt = task.dueAt else { return false }
                return CalendarMath.isSameMonth(dueAt, month, calendar: calendar)
            }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }


}

#Preview {
    CalendarScreen()
        .environment(AppRouter())
        .modelContainer(PreviewSampleData.make().container)
}
