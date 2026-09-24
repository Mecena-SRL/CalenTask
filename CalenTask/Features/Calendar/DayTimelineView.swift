import SwiftUI
import SwiftData

/// Time-blocking (D14, ridisegnato v8): il giorno come griglia oraria.
/// - **Tocca** un punto vuoto per creare un'attività di 1h; **premi e trascina**
///   per darle subito una durata, poi ne aggiungi i dati.
/// - I **blocchi** sono ricchi e adattivi: quando c'è spazio (eventi lunghi,
///   schermo grande) mostrano contesto, barra di completamento e i **sotto-task
///   spuntabili al volo**, disposti su più colonne per riempire la larghezza.
/// Il blocco-evento (`TimeBlockView`) è condiviso con la Settimana e vive in
/// `TimelineBlockView.swift`.
struct DayTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    let day: Date
    /// Tasks that already live on this day's grid (startAt within day).
    let plannedTasks: [TodoTask]
    /// Altezza di un'ora: regolabile col pinch (densità della giornata).
    var hourHeight: CGFloat = 56
    /// I membri dello spazio, per le iniziali dell'assegnatario sui blocchi.
    var people: [UserProfile] = []
    /// Ore lavorative: fuori si ombreggia; decide anche dove si apre.
    var workHours: Range<Int>?
    /// Da dove entra il giorno nuovo (avanti = da destra).
    var transitionEdge: Edge = .trailing
    /// Cambia quando si preme "Oggi": la griglia torna sull'ora corrente.
    var scrollToNowToken = 0

    private let labelWidth: CGFloat = 52
    private let snapMinutes = 15
    private let calendar = Calendar.app

    /// Anteprima del blocco mentre si trascina per creare.
    @State private var draftRange: (start: CGFloat, end: CGFloat)?
    var body: some View {
        grid
    }

    // MARK: Grid

    private var initialHour: Int {
        CalendarGridMetrics.initialScrollHour(
            showsToday: calendar.isDateInToday(day), now: .now,
            workStart: workHours?.lowerBound ?? 8, calendar: calendar
        )
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    CalendarHourLabels(hourHeight: hourHeight, width: labelWidth, idPrefix: "hour-")
                    ZStack(alignment: .topLeading) {
                        CalendarHourGridCanvas(hourHeight: hourHeight, workHours: workHours)
                        // Solo gli eventi cambiano col giorno: la griglia resta
                        // ferma (e lo scroll al suo posto), il giorno nuovo
                        // scivola dentro dal lato giusto.
                        interactiveLayer
                            .id(calendar.startOfDay(for: day))
                            .transition(.push(from: transitionEdge))
                    }
                    .frame(height: hourHeight * 24)
                    .clipped()
                    .dropDestination(for: String.self) { items, location in
                        handleDrop(items, at: location)
                    } isTargeted: { _ in }
                }
                .overlay(alignment: .topLeading) {
                    CalendarNowIndicator(
                        hourHeight: hourHeight, labelWidth: labelWidth,
                        todayColumn: calendar.isDateInToday(day) ? 0 : nil
                    )
                }
                .padding(.vertical, DS.s)
            }
            .frame(maxHeight: .infinity)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            .onAppear {
                proxy.scrollTo("hour-\(initialHour)", anchor: .top)
            }
            .onChange(of: scrollToNowToken) { _, _ in
                withAnimation(.dsSoft) { proxy.scrollTo("hour-\(initialHour)", anchor: .top) }
            }
        }
    }

    /// Layer interattivo: superficie per creare (tap/press-drag), anteprima e
    /// blocchi a cascata quando si sovrappongono.
    private var interactiveLayer: some View {
        GeometryReader { geo in
            let laneX: CGFloat = DS.xs
            let laneWidth = max(0, geo.size.width - laneX - DS.m)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(tapCreateGesture)
                    .simultaneousGesture(dragCreateGesture)

                if let draft = draftRange {
                    draftPreview(draft, width: laneWidth)
                        .offset(x: laneX, y: draft.start)
                }

                // Sovrapposizioni a CASCATA: le carte di un cluster si impilano
                // sfalsate verso destra; la carta in primo piano (l'ultima, o
                // quella toccata) si vede intera, le altre spuntano a sinistra.
                CalendarCascadeLayer(
                    clusters: CalendarMath.overlapClusters(for: plannedTasks),
                    people: people,
                    hourHeight: hourHeight,
                    laneWidth: laneWidth,
                    leadingInset: laneX
                )
            }
        }
    }

    /// Anteprima del blocco mentre si trascina per crearlo, con l'orario.
    private func draftPreview(_ draft: (start: CGFloat, end: CGFloat), width: CGFloat) -> some View {
        let startMinutes = snap(minutes(at: draft.start))
        let endMinutes = max(snap(minutes(at: draft.end)), startMinutes + 15)
        return RoundedRectangle(cornerRadius: DS.Radius.small)
            .fill(Color.accentColor.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .strokeBorder(Color.accentColor, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                Text(CalendarGridMetrics.rangeLabel(startMinutes, endMinutes))
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .padding(DS.xs)
            }
            .frame(width: width, height: max(draft.end - draft.start, 14))
            .allowsHitTesting(false)
            .sensoryFeedback(.selection, trigger: endMinutes)
    }

    // MARK: Creazione (tap / press-drag)

    /// Doppio-tap su un vuoto = crea 1h (il singolo creava per sbaglio).
    private var tapCreateGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let start = snap(minutes(at: value.location.y))
                createTimedTask(startMinutes: start, endMinutes: start + 60)
            }
    }

    private var dragCreateGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 2))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    let a = drag.startLocation.y, b = drag.location.y
                    draftRange = (min(a, b), max(a, b))
                }
            }
            .onEnded { value in
                if case .second(_, let drag?) = value {
                    let a = snap(minutes(at: drag.startLocation.y))
                    let b = snap(minutes(at: drag.location.y))
                    createTimedTask(startMinutes: min(a, b), endMinutes: max(a, b))
                }
                draftRange = nil
            }
    }

    private func createTimedTask(startMinutes: Int, endMinutes: Int) {
        let startM = max(0, min(startMinutes, 23 * 60 + 45))
        let endM = min(max(endMinutes, startM + 15), 24 * 60)
        guard let start = calendar.date(
            bySettingHour: startM / 60, minute: startM % 60, second: 0, of: day
        ) else { return }
        let end = start.addingTimeInterval(TimeInterval((endM - startM) * 60))
        CalendarActions.createTask(start: start, end: end, in: modelContext, router: router)
    }

    private func minutes(at y: CGFloat) -> Int {
        max(0, min(Int(y / hourHeight * 60), 24 * 60 - 1))
    }

    private func snap(_ m: Int) -> Int {
        (m / snapMinutes) * snapMinutes
    }

    // MARK: Drop

    private func handleDrop(_ items: [String], at location: CGPoint) -> Bool {
        guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { $0.id == id })
        guard let task = try? modelContext.fetch(descriptor).first else { return false }

        let rawMinutes = Int(location.y / hourHeight * 60)
        let snapped = (rawMinutes / snapMinutes) * snapMinutes
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
}

#Preview {
    let preview = PreviewSampleData.make()
    return DayTimelineView(
        day: .now,
        plannedTasks: preview.tasks.filter { $0.startAt != nil }
    )
    .padding()
    .frame(height: 600)
    .environment(AppRouter())
    .modelContainer(preview.container)
}
