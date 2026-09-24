import SwiftUI

// MARK: - Block

/// Un blocco programmato su una griglia oraria: trascina per spostare, trascina
/// il bordo basso per ridimensionare, tocca per aprire. Il contenuto si
/// **arricchisce con lo spazio**: meta (priorità/assegnatario) a destra,
/// contesto, barra di completamento e i sotto-task spuntabili su più colonne.
///
/// Condiviso dalla **Griglia del Giorno** (`DayTimelineView`, una corsia a tutta
/// larghezza) e dalla **Settimana** (`WeekGridView`, N corsie strette): le
/// stesse soglie `width`/height fanno disclosure progressiva — titolo+ora nelle
/// colonne strette della settimana, blocco ricco nel giorno o nella vista a
/// pochi giorni.
struct TimeBlockView: View {
    @Environment(AppRouter.self) private var router
    @Bindable var task: TodoTask
    var people: [UserProfile] = []
    let hourHeight: CGFloat
    let snapMinutes: Int
    let yPosition: CGFloat
    let height: CGFloat
    let xOffset: CGFloat
    let width: CGFloat
    /// La carta fa parte di una pila di sovrapposizioni (cascata): fondo opaco,
    /// ombra di stacco e tap-per-portare-avanti. Falso = blocco isolato.
    var cascaded: Bool = false
    /// La carta è in primo piano nel suo cluster: solo lei si sposta/ridimensiona
    /// e il tap la apre; le carte sepolte col tap salgono in cima.
    var isFront: Bool = true
    /// La carta è **sollevata** dall'utente (hover/tap), non solo in cima a
    /// riposo: anima — leggera scala + ombra più marcata — per dire "sono io".
    var isLifted: Bool = false
    /// Porta questa carta in primo piano (tap su una carta sepolta).
    var onRaise: (() -> Void)?
    /// Il cursore è entrato/uscito dalla carta (hover, solo Mac): il contenitore
    /// usa questo per sollevare quella sotto il cursore e tornare alla gerarchia
    /// quando ci si allontana.
    var onHover: ((Bool) -> Void)?
    /// Inizio/fine di uno spostamento o ridimensionamento: il contenitore
    /// porta il blocco sopra a tutti mentre si muove.
    var onDragStateChange: ((Bool) -> Void)?

    @State private var dragOffset: CGFloat = 0
    @State private var resizeOffset: CGFloat = 0
    @State private var isMoving = false
    @State private var isResizing = false

    /// Spostamento agganciato ai 15 minuti: il blocco scatta da una tacca
    /// all'altra (come Calendario di Apple) e l'orario in anteprima è esatto.
    private var moveMinutes: Int { snappedMinutes(dragOffset) }
    private var resizeMinutes: Int { snappedMinutes(resizeOffset) }
    private var moveOffset: CGFloat { CGFloat(moveMinutes) / 60 * hourHeight }
    private var resizeDelta: CGFloat { CGFloat(resizeMinutes) / 60 * hourHeight }
    private var isManipulating: Bool { isMoving || isResizing }

    private var tint: Color {
        task.project.map { Color(hex: $0.colorHex) } ?? Color.accentColor
    }

    /// Un'attività spuntabile (non un evento "puro").
    private var isCheckable: Bool {
        task.kind == .task || task.kind == .reminder
    }

    private var hasContext: Bool {
        task.project != nil
            || !(task.locationName ?? "").isEmpty
            || task.videoCallURL != nil
            || !task.tags.isEmpty
    }

    var body: some View {
        let blockHeight = max(height + resizeDelta, hourHeight / 4)
        // I sotto-task si leggono (relazione + ordinamento) solo se il blocco
        // è abbastanza grande da mostrarli: le carte strette della settimana
        // non pagano il costo a ogni frame di pinch.
        let roomForProgress = blockHeight >= 50 && width >= 108
        let subtasks = roomForProgress ? task.liveSubtasks : []
        let total = subtasks.count
        let doneCount = subtasks.filter(\.isDone).count
        let hasSubtasks = total > 0

        let showsTime = blockHeight >= 40
        let showsContext = hasContext && blockHeight >= 56 && width >= 150
        let showsProgress = hasSubtasks && blockHeight >= 50 && width >= 108
        let showsSubtasks = hasSubtasks && blockHeight >= 82 && width >= 150

        VStack(alignment: .leading, spacing: 3) {
            header(tall: blockHeight >= 58)

            if showsTime { timeLine }

            if showsContext { contextChips }

            if showsProgress {
                progressRow(
                    fraction: Double(doneCount) / Double(max(1, total)),
                    done: doneCount, total: total
                )
            }

            if showsSubtasks {
                subtaskGrid(
                    subtasks,
                    blockHeight: blockHeight,
                    progressShown: showsProgress,
                    contextShown: showsContext
                )
            }

            Spacer(minLength: 0)
        }
        .padding(DS.s)
        .padding(.leading, DS.xs)
        .frame(width: width, height: blockHeight, alignment: .topLeading)
        .dsEventBlock(tint: tint, isDone: task.isDone)
        // Cascata: fondo opaco per OCCLUDERE le carte sotto (il fill tinta è al
        // 15%, da solo si fonderebbe) + ombra di stacco verso la carta a
        // sinistra che spunta.
        .background {
            if cascaded {
                RoundedRectangle(cornerRadius: DS.Radius.small).fill(DSColor.surface)
            }
        }
        // Sollevamento: la carta attiva (hover/tap) o in movimento cresce
        // appena e proietta un'ombra più marcata — è questo che si anima
        // quando "sale", non lo z-index (istantaneo). A riposo l'ombra è
        // solo di stacco.
        .shadow(
            color: shadowColor,
            radius: isManipulating ? 10 : (cascaded ? (isLifted ? 7 : 2) : 0),
            x: cascaded && !isManipulating ? -1 : 0,
            y: isManipulating ? 5 : (isLifted ? 3 : 0)
        )
        .scaleEffect(isManipulating ? 1.03 : (isLifted ? 1.02 : 1), anchor: .center)
        // Mentre si sposta o si allunga: l'orario d'arrivo sopra il blocco.
        .overlay(alignment: .topLeading) {
            if isManipulating {
                Text(previewRange)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint, in: Capsule())
                    .fixedSize()
                    .offset(y: -20)
                    .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        // …e dove era prima, tratteggiato, per capire di quanto si sposta.
        .background(alignment: .topLeading) {
            if isMoving, moveMinutes != 0 {
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .strokeBorder(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: width, height: max(height, hourHeight / 4))
                    .offset(y: -moveOffset)
            }
        }
        .overlay(alignment: .bottom) {
            // S5 — maniglia di resize VISIBILE: solo la carta in primo piano.
            if isFront {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(tint.opacity(0.45))
                        .frame(width: 28, height: 3)
                        .padding(.bottom, 3)
                }
                .frame(height: 14)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(resizeGesture)
                #if os(macOS)
                .onHover { hovering in
                    if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                #endif
            }
        }
        .offset(x: xOffset, y: yPosition + moveOffset)
        .onTapGesture {
            if cascaded && !isFront {
                withAnimation(.dsQuick) { onRaise?() }
            } else {
                open()
            }
        }
        // Solo la carta in primo piano si trascina (spostamento ora); le sepolte
        // restano "tap per portare avanti", senza rubare lo scroll.
        .gesture(moveGesture, including: isFront ? .all : .subviews)
        #if os(macOS)
        // Su Mac, passare sopra una carta la segnala al contenitore, che solleva
        // quella sotto il cursore e ripristina la gerarchia quando si esce.
        .onHover { hovering in
            if cascaded { onHover?(hovering) }
        }
        #endif
        .taskContextMenu(task)
        // Solo i riposizionamenti discreti e il sollevamento animano; durante il
        // pinch i blocchi seguono dal vivo la densità, senza animazione a frame.
        .animation(.dsQuick, value: xOffset)
        .animation(.dsQuick, value: width)
        .animation(.dsQuick, value: isLifted)
        .animation(.dsQuick, value: isManipulating)
        // Lo scatto da una tacca all'altra: veloce e con un tocco tattile.
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.86), value: moveMinutes)
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.86), value: resizeMinutes)
        .sensoryFeedback(.selection, trigger: moveMinutes)
        .sensoryFeedback(.selection, trigger: resizeMinutes)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private var shadowColor: Color {
        if isManipulating { return .black.opacity(0.25) }
        guard cascaded else { return .clear }
        return .black.opacity(isLifted ? 0.22 : (isFront ? 0.14 : 0.06))
    }

    /// L'orario che il blocco avrà rilasciandolo qui.
    private var previewRange: String {
        guard let startAt = task.startAt else { return "" }
        let end = task.endAt ?? startAt.addingTimeInterval(3600)
        let shift = TimeInterval(moveMinutes * 60)
        let newStart = startAt.addingTimeInterval(shift)
        let newEnd = isResizing
            ? max(end.addingTimeInterval(TimeInterval(resizeMinutes * 60)), startAt.addingTimeInterval(15 * 60))
            : end.addingTimeInterval(shift)
        return "\(newStart.dsTimeLabel) – \(newEnd.dsTimeLabel)"
    }

    private func open() {
        #if os(macOS)
        router.inspect(taskID: task.id)
        #else
        router.open(taskID: task.id)
        #endif
    }

    // MARK: Pezzi del blocco

    private func header(tall: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.xs) {
            if isCheckable {
                DSCheckToggle(isDone: task.isDone, font: .callout) {
                    withAnimation(.dsSoft) { task.toggleDone() }
                }
            }
            Text(task.title)
                .font(.dsCaption.weight(.semibold))
                .strikethrough(task.isDone)
                .lineLimit(tall ? 2 : 1)
            Spacer(minLength: DS.xs)
            metaCluster
        }
    }

    /// Cluster a destra dell'header: priorità + iniziali assegnatario. Riempie
    /// lo spazio orizzontale che prima restava vuoto sul desktop.
    @ViewBuilder
    private var metaCluster: some View {
        HStack(spacing: 4) {
            if task.priority == .high || task.priority == .urgent {
                Image(systemName: task.priority == .urgent ? "exclamationmark.2" : "flag.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DSColor.priority(task.priority))
            }
            if let initials = assigneeInitials, width >= 150 {
                Text(initials)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.quaternary.opacity(0.7)))
            }
        }
    }

    private var timeLine: some View {
        HStack(spacing: DS.xs) {
            if let startAt = task.startAt {
                let end = task.endAt ?? startAt.addingTimeInterval(3600)
                Text("\(startAt.dsTimeLabel) – \(end.dsTimeLabel)")
                if width >= 188 {
                    Text("· \(durationLabel(startAt, end))")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .font(.dsCaption)
        .opacity(0.8)
        .lineLimit(1)
    }

    @ViewBuilder
    private var contextChips: some View {
        HStack(spacing: DS.s) {
            if let project = task.project {
                HStack(spacing: 3) {
                    Circle().fill(Color(hex: project.colorHex)).frame(width: 6, height: 6)
                    Text(project.name).lineLimit(1)
                }
            }
            if let location = task.locationName, !location.isEmpty {
                Label(location, systemImage: "mappin")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
            if task.videoCallURL != nil {
                Image(systemName: "video.fill")
            }
            if width >= 240 {
                ForEach(task.tags.prefix(2), id: \.id) { tag in
                    Text("#\(tag.name)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10))
        .opacity(0.85)
    }

    /// Barra di completamento curata: traccia tenue + riempimento sfumato,
    /// angoli tondi, con il conteggio a fianco.
    private func progressRow(fraction: Double, done: Int, total: Int) -> some View {
        HStack(spacing: DS.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.16))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(task.isDone ? 0.5 : 0.85), tint],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 6)
            .animation(.dsSoft, value: fraction)

            Text("\(done)/\(total)")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// I sotto-task DENTRO il blocco, su più colonne per riempire la larghezza
    /// (1 colonna stretto, fino a 3 sul desktop). Spuntabili al volo.
    private func subtaskGrid(_ subtasks: [TodoTask], blockHeight: CGFloat,
                             progressShown: Bool, contextShown: Bool) -> some View {
        let columns = max(1, min(3, Int(width / 190)))
        let reserved: CGFloat = 42
            + (contextShown ? 16 : 0)
            + (progressShown ? 12 : 0)
        let maxRows = max(1, Int((blockHeight - reserved) / 20))
        let capacity = columns * maxRows
        let truncated = subtasks.count > capacity
        let visible = truncated ? Array(subtasks.prefix(max(1, capacity - 1))) : subtasks
        let gridColumns = Array(
            repeating: GridItem(.flexible(), spacing: DS.m, alignment: .leading),
            count: columns
        )
        return VStack(alignment: .leading, spacing: 2) {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 2) {
                ForEach(visible) { sub in
                    SubtaskCheckRow(subtask: sub)
                }
            }
            if truncated {
                Text("+\(subtasks.count - visible.count) altre")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var assigneeInitials: String? {
        guard let id = task.assigneeID,
              let person = people.first(where: { $0.id == id }) else { return nil }
        let parts = person.name.split(separator: " ").prefix(2)
        let initials = parts.map { String($0.prefix(1)).uppercased() }.joined()
        return initials.isEmpty ? nil : initials
    }

    private func durationLabel(_ start: Date, _ end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let hours = minutes / 60, mins = minutes % 60
        if hours == 0 { return "\(mins)m" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }

    // MARK: Gesti

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if !isMoving {
                    isMoving = true
                    onDragStateChange?(true)
                }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let minutes = snappedMinutes(value.translation.height)
                // Il blocco è già sulla tacca d'arrivo: si azzera lo scarto e
                // si scrive l'orario nello stesso passaggio, senza salti.
                withAnimation(.dsQuick) {
                    dragOffset = 0
                    isMoving = false
                    shiftStart(byMinutes: minutes)
                }
                onDragStateChange?(false)
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !isResizing {
                    isResizing = true
                    onDragStateChange?(true)
                }
                resizeOffset = value.translation.height
            }
            .onEnded { value in
                let minutes = snappedMinutes(value.translation.height)
                withAnimation(.dsQuick) {
                    resizeOffset = 0
                    isResizing = false
                    stretch(byMinutes: minutes)
                }
                onDragStateChange?(false)
            }
    }

    /// Scarto in minuti arrotondato alla tacca più vicina (non troncato:
    /// trascinare di 10' verso l'alto arriva a -15', come ci si aspetta).
    private func snappedMinutes(_ translation: CGFloat) -> Int {
        guard hourHeight > 0 else { return 0 }
        let raw = Double(translation / hourHeight * 60)
        return Int((raw / Double(snapMinutes)).rounded()) * snapMinutes
    }

    private func shiftStart(byMinutes minutes: Int) {
        guard minutes != 0, let startAt = task.startAt else { return }
        let delta = TimeInterval(minutes * 60)
        task.startAt = startAt.addingTimeInterval(delta)
        task.endAt = task.endAt?.addingTimeInterval(delta)
        task.touch()
    }

    private func stretch(byMinutes minutes: Int) {
        guard minutes != 0, let startAt = task.startAt else { return }
        let currentEnd = task.endAt ?? startAt.addingTimeInterval(3600)
        let newEnd = max(
            currentEnd.addingTimeInterval(TimeInterval(minutes * 60)),
            startAt.addingTimeInterval(TimeInterval(15 * 60))
        )
        task.endAt = newEnd
        task.touch()
    }
}

// MARK: - Riga sotto-task dentro al blocco

/// Un sotto-task spuntabile dal blocco-evento: `@Bindable` così la spunta si
/// aggiorna all'istante senza aprire il dettaglio.
struct SubtaskCheckRow: View {
    @Bindable var subtask: TodoTask

    var body: some View {
        HStack(spacing: DS.xs) {
            DSCheckToggle(isDone: subtask.isDone, font: .caption2) {
                withAnimation(.dsSoft) { subtask.toggleDone() }
            }
            Text(subtask.title)
                .font(.system(size: 11))
                .strikethrough(subtask.isDone)
                .foregroundStyle(subtask.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
