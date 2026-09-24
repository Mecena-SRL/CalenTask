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

    private let labelWidth: CGFloat = 48
    private let snapMinutes = 15
    private let calendar = Calendar.app

    /// Anteprima del blocco mentre si trascina per creare.
    @State private var draftRange: (start: CGFloat, end: CGFloat)?
    var body: some View {
        grid
    }

    // MARK: Grid

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourLines
                    nowIndicator
                    interactiveLayer
                }
                .frame(height: hourHeight * 24)
                .dropDestination(for: String.self) { items, location in
                    handleDrop(items, at: location)
                } isTargeted: { _ in }
            }
            .frame(maxHeight: .infinity)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            .onAppear {
                proxy.scrollTo("hour-8", anchor: .top)
            }
        }
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: DS.s) {
                    Text(String(format: "%02d", hour))
                        .font(.dsNumeric)
                        .foregroundStyle(.tertiary)
                        .frame(width: labelWidth - DS.s, alignment: .trailing)
                    VStack(spacing: 0) {
                        Divider()
                        Spacer()
                        Rectangle()
                            .fill(DSColor.hairline.opacity(0.4))
                            .frame(height: 0.5)
                        Spacer()
                    }
                }
                .frame(height: hourHeight)
                .id("hour-\(hour)")
            }
        }
    }

    @ViewBuilder
    private var nowIndicator: some View {
        if calendar.isDate(day, inSameDayAs: .now) {
            let minutes = minutesIntoDay(.now)
            DSNowLine()
                .offset(y: yPosition(forMinutes: minutes))
                .padding(.leading, labelWidth - 4)
        }
    }

    /// Layer interattivo: superficie per creare (tap/press-drag), anteprima e
    /// blocchi posizionati in colonne quando si sovrappongono.
    private var interactiveLayer: some View {
        GeometryReader { geo in
            let laneX = labelWidth + DS.s
            let laneWidth = max(0, geo.size.width - laneX - DS.m)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .padding(.leading, laneX)
                    .gesture(tapCreateGesture)
                    .simultaneousGesture(dragCreateGesture)

                if let draft = draftRange {
                    RoundedRectangle(cornerRadius: DS.Radius.small)
                        .fill(Color.accentColor.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.small)
                                .strokeBorder(Color.accentColor, lineWidth: 1)
                        )
                        .frame(width: laneWidth, height: max(draft.end - draft.start, 14))
                        .offset(x: laneX, y: draft.start)
                        .allowsHitTesting(false)
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
            assertionFailure("create timed task: \(error)")
        }
    }

    private func minutes(at y: CGFloat) -> Int {
        max(0, min(Int(y / hourHeight * 60), 24 * 60 - 1))
    }

    private func snap(_ m: Int) -> Int {
        (m / snapMinutes) * snapMinutes
    }

    // MARK: Geometry & mutations

    private func minutesIntoDay(_ date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func yPosition(forMinutes minutes: Int) -> CGFloat {
        CGFloat(minutes) / 60 * hourHeight
    }

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
