import SwiftUI
import SwiftData

/// Settimana a griglia oraria (D42, rivista in F23; allineata al Giorno in v8):
/// header compatto su una riga, ore che riempiono lo spazio (altezza adattiva),
/// linea "adesso", scadenze all-day in testa. Ogni colonna è una **corsia
/// giornaliera** che condivide le interazioni della Griglia del Giorno:
/// - eventi sovrapposti **a cascata** (`CalendarMath.overlapClusters`): carte
///   sfalsate, tap/hover per portarne una avanti;
/// - **tocca** un punto vuoto per creare 1h, **premi e trascina** per la durata;
/// - **trascina** un'attività (anche dalla fascia all-day) su un orario;
/// - i **blocchi** sono gli stessi del Giorno (`TimeBlockView`): si spostano e
///   ridimensionano trascinando, si spuntano al volo, si arricchiscono se c'è
///   spazio (vista a pochi giorni).
/// Il tap sull'intestazione del giorno scende nella vista giornaliera.
struct WeekGridView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    let weekStart: Date
    /// S5 — vista N-giorni: 2–9 colonne (7 = settimana classica).
    var dayCount: Int = 7
    let data: CalendarTaskIndex
    /// I membri dello spazio, per le iniziali dell'assegnatario sui blocchi.
    var people: [UserProfile] = []
    var showsWeather = true
    /// Ore lavorative: fuori si ombreggia; decide anche dove si apre.
    var workHours: Range<Int>?
    /// Da dove entra il periodo nuovo (avanti = da destra).
    var transitionEdge: Edge = .trailing
    /// Cambia quando si preme "Oggi": la griglia torna sull'ora corrente.
    var scrollToNowToken = 0
    var onOpenDay: (Date) -> Void = { _ in }

    /// F23 — l'altezza dell'ora segue lo spazio: ~14 ore visibili senza
    /// scroll, mai sotto i 34pt né sopra i 64pt.
    @State private var viewportHeight: CGFloat = 600

    /// Anteprima del blocco mentre si trascina per creare (con il giorno scelto).
    @State private var draftRange: (day: Date, start: CGFloat, end: CGFloat)?
    private var hourHeight: CGFloat {
        min(64, max(34, viewportHeight / 14))
    }

    private let labelWidth: CGFloat = 46
    private let columnGap: CGFloat = 2
    private let snapMinutes = 15
    private let calendar = Calendar.app

    private var days: [Date] {
        (0..<max(dayCount, 1)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart)
        }
    }

    private var periodID: Date { calendar.startOfDay(for: weekStart) }

    private var initialHour: Int {
        CalendarGridMetrics.initialScrollHour(
            showsToday: days.contains { calendar.isDateInToday($0) }, now: .now,
            workStart: workHours?.lowerBound ?? 8, calendar: calendar
        )
    }

    var body: some View {
        let days = days
        VStack(spacing: 0) {
            header(days: days)
            allDayRow(days: days, data: data)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    grid(days: days, data: data)
                }
                .onAppear { proxy.scrollTo("week-hour-\(initialHour)", anchor: .top) }
                .onChange(of: scrollToNowToken) { _, _ in
                    withAnimation(.dsSoft) { proxy.scrollTo("week-hour-\(initialHour)", anchor: .top) }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    viewportHeight = height
                }
            }
        }
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
    }

    // MARK: Header

    /// F23 — una sola riga per giorno ("Lun 16" + meteo): il grosso dello
    /// spazio verticale va alle ore, non alla testata. A sinistra il numero
    /// della settimana.
    private func header(days: [Date]) -> some View {
        HStack(spacing: 0) {
            Text("S\(calendar.component(.weekOfYear, from: weekStart))")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: labelWidth)
                .contentTransition(.numericText())
            ZStack {
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        dayHeaderButton(day)
                    }
                }
                .id(periodID)
                .transition(.push(from: transitionEdge))
            }
            .clipped()
        }
        .padding(.vertical, DS.xs)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func dayHeaderButton(_ day: Date) -> some View {
        Button {
            onOpenDay(day)
        } label: {
            HStack(spacing: DS.xs) {
                Text(day.appFormatted(.dateTime.weekday(.abbreviated)))
                    .font(.dsCaption)
                    .foregroundStyle(day.isToday ? .white : .secondary)
                Text("\(calendar.component(.day, from: day))")
                    .font(.dsNumeric.weight(.semibold))
                    .foregroundStyle(day.isToday ? .white : .primary)
                if showsWeather, let forecast = WeatherService.shared.forecast(for: day) {
                    Image(systemName: forecast.symbolName)
                        .symbolRenderingMode(day.isToday ? .monochrome : .multicolor)
                        .foregroundStyle(day.isToday ? .white : .primary)
                        .font(.system(size: 9))
                }
            }
            .padding(.horizontal, DS.s)
            .padding(.vertical, 3)
            .background {
                if day.isToday {
                    Capsule().fill(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Apri \(day.appFormatted(.dateTime.weekday(.wide).day().month()))")
    }

    /// Scadenze e all-day della settimana, compatte sopra la griglia.
    /// Le chip sono trascinabili su un orario della griglia (come nel Giorno).
    @ViewBuilder
    private func allDayRow(days: [Date], data: CalendarTaskIndex) -> some View {
        if days.contains(where: { !data.allDayTasks(on: $0).isEmpty }) {
            HStack(alignment: .top, spacing: 0) {
                Text("∞")
                    .font(.dsCaption)
                    .foregroundStyle(.tertiary)
                    .frame(width: labelWidth)
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            // Le chip si dimensionano sul contenuto (niente larghezza
                            // fissa sproporzionata), allineate a sinistra nel giorno.
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(data.allDayTasks(on: day).prefix(3), id: \.id) { task in
                                    Text(task.title)
                                        .font(.system(size: 9, weight: .medium))
                                        .lineLimit(1)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(itemTint(task).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                        .foregroundStyle(itemTint(task))
                                        .draggable(task.id.uuidString)
                                        .taskContextMenu(task)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 1)
                        }
                    }
                    .id(periodID)
                    .transition(.push(from: transitionEdge))
                }
                .clipped()
            }
            .padding(.bottom, DS.xs)
        }
    }

    // MARK: Grid

    private func grid(days: [Date], data: CalendarTaskIndex) -> some View {
        HStack(alignment: .top, spacing: 0) {
            CalendarHourLabels(hourHeight: hourHeight, width: labelWidth, idPrefix: "week-hour-")
            ZStack(alignment: .topLeading) {
                // Un solo disegno per ore, mezz'ore, weekend e fuori orario
                // di TUTTE le colonne (prima: 24 viste × colonna).
                CalendarHourGridCanvas(
                    hourHeight: hourHeight,
                    columns: days.count,
                    weekendColumns: Set(days.indices.filter { calendar.isDateInWeekend(days[$0]) }),
                    workHours: workHours
                )
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        dayColumn(day, tasks: data.timedTasks(on: day))
                            .frame(maxWidth: .infinity)
                    }
                }
                .id(periodID)
                .transition(.push(from: transitionEdge))
            }
            .frame(height: hourHeight * 24)
            .clipped()
        }
        .overlay(alignment: .topLeading) {
            CalendarNowIndicator(
                hourHeight: hourHeight, labelWidth: labelWidth,
                columns: days.count,
                todayColumn: days.firstIndex { calendar.isDateInToday($0) }
            )
        }
        .padding(.vertical, DS.s)
    }

    /// Una corsia giornaliera: superficie per creare, anteprima e i blocchi a
    /// cascata per le sovrapposizioni (lo sfondo è il Canvas comune).
    private func dayColumn(_ day: Date, tasks: [TodoTask]) -> some View {
        let clusters = CalendarMath.overlapClusters(for: tasks)
        return GeometryReader { geo in
            let laneWidth = max(0, geo.size.width - columnGap)
            ZStack(alignment: .topLeading) {
                // Superficie di creazione (sotto i blocchi).
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(tapCreateGesture(day))
                    .simultaneousGesture(dragCreateGesture(day))

                if let draft = draftRange, calendar.isDate(draft.day, inSameDayAs: day) {
                    draftPreview(start: draft.start, end: draft.end, width: laneWidth)
                        .offset(x: 1, y: draft.start)
                }

                // Sovrapposizioni a CASCATA, come nel Giorno: nelle colonne
                // strette della settimana evita le fettine illeggibili — le
                // carte si impilano sfalsate, tap/hover per portarne una avanti.
                CalendarCascadeLayer(
                    clusters: clusters,
                    people: people,
                    hourHeight: hourHeight,
                    laneWidth: laneWidth,
                    leadingInset: 1,
                    minimumMinutes: 20
                )
            }
            .dropDestination(for: String.self) { dropped, location in
                handleDrop(dropped, on: day, at: location)
            } isTargeted: { _ in }
        }
    }

    /// Anteprima del blocco mentre si trascina per crearlo, con l'orario.
    private func draftPreview(start: CGFloat, end: CGFloat, width: CGFloat) -> some View {
        let startMinutes = snap(minutes(at: start))
        let endMinutes = max(snap(minutes(at: end)), startMinutes + 15)
        return RoundedRectangle(cornerRadius: DS.Radius.small)
            .fill(Color.accentColor.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .strokeBorder(Color.accentColor, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                Text(CalendarGridMetrics.rangeLabel(startMinutes, endMinutes))
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(3)
            }
            .frame(width: width, height: max(end - start, 12))
            .allowsHitTesting(false)
            .sensoryFeedback(.selection, trigger: endMinutes)
    }

    // MARK: Creazione (tap / press-drag), condivisa col Giorno

    /// Doppio-tap su un vuoto = crea 1h (il singolo creava per sbaglio).
    private func tapCreateGesture(_ day: Date) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let start = snap(minutes(at: value.location.y))
                createTimedTask(on: day, startMinutes: start, endMinutes: start + 60)
            }
    }

    private func dragCreateGesture(_ day: Date) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 2))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    let a = drag.startLocation.y, b = drag.location.y
                    draftRange = (day, min(a, b), max(a, b))
                }
            }
            .onEnded { value in
                if case .second(_, let drag?) = value {
                    let a = snap(minutes(at: drag.startLocation.y))
                    let b = snap(minutes(at: drag.location.y))
                    createTimedTask(on: day, startMinutes: min(a, b), endMinutes: max(a, b))
                }
                draftRange = nil
            }
    }

    private func createTimedTask(on day: Date, startMinutes: Int, endMinutes: Int) {
        let startM = max(0, min(startMinutes, 23 * 60 + 45))
        let endM = min(max(endMinutes, startM + 15), 24 * 60)
        guard let start = calendar.date(
            bySettingHour: startM / 60, minute: startM % 60, second: 0, of: day
        ) else { return }
        let end = start.addingTimeInterval(TimeInterval((endM - startM) * 60))
        do {
            let (workspace, me) = try SeedService.ensureSeed(in: modelContext)
            let target = WorkspaceScope.creationTarget(in: modelContext, fallback: workspace)
            let task = TodoTask(
                workspaceID: target.id,
                title: "Nuova attività",
                kind: .task,
                startAt: start,
                endAt: end,
                createdByID: me.id
            )
            modelContext.insert(task)
            try? modelContext.save()
            NotificationService.shared.sync(task: task)
            // "poi aggiungo i dati": apri subito l'editor.
            #if os(macOS)
            router.inspect(taskID: task.id)
            #else
            router.open(taskID: task.id)
            #endif
        } catch {
            reportFailure("create timed task (week): \(error)")
        }
    }

    private func handleDrop(_ items: [String], on day: Date, at location: CGPoint) -> Bool {
        guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { $0.id == id })
        guard let task = try? modelContext.fetch(descriptor).first else { return false }

        let snapped = snap(minutes(at: location.y))
        let clampedMinutes = min(max(snapped, 0), 23 * 60)
        guard let start = calendar.date(
            bySettingHour: clampedMinutes / 60, minute: clampedMinutes % 60, second: 0, of: day
        ) else { return false }

        withAnimation(.dsQuick) {
            let duration = task.startAt.flatMap { start0 in
                task.endAt.map { $0.timeIntervalSince(start0) }
            } ?? 3600
            task.startAt = start
            task.endAt = start.addingTimeInterval(max(900, duration))
            task.touch()
        }
        return true
    }

    private func minutes(at y: CGFloat) -> Int {
        max(0, min(Int(y / hourHeight * 60), 24 * 60 - 1))
    }

    private func snap(_ m: Int) -> Int {
        (m / snapMinutes) * snapMinutes
    }

    private func itemTint(_ task: TodoTask) -> Color {
        task.accentTagColorHex.map { Color(hex: $0) }
            ?? task.project.map { Color(hex: $0.colorHex) }
            ?? .accentColor
    }

}
