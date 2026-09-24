import SwiftUI
import SwiftData

/// Gantt 2.0 (D8/D15, F38, G8-G15): colonna dei nomi fissa a sinistra
/// (la timeline parte DOPO le scritte), gerarchia fase → attività →
/// sotto-attività con righe espandibili, vista semplice (barre colorate)
/// o complessa (titolo+fase, etichetta, progresso), barre che si riempiono
/// col completamento (15% → 100%), maniglie di durata, vincoli con frecce
/// live, menu contestuali ovunque, colori per giorno della settimana.
struct ProjectGanttView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Bindable var project: Project

    @Query(filter: #Predicate<TaskDependency> { $0.deletedAt == nil })
    private var allDependencies: [TaskDependency]

    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil })
    private var people: [UserProfile]

    /// Live preview of a dependency being drawn from a bar's link handle.
    @State private var linkDraft: LinkDraft?

    /// G10/G14 — righe con figli (fasi E attività) espandibili.
    @State private var collapsedRows: Set<UUID> = []

    /// G10 — vista complessa: righe alte con titolo+fase, etichetta, progresso.
    @AppStorage("ganttComplexRows") private var complexRows = false

    /// G15 — colori per giorno della settimana ("2:#E5484D,3:#30A46C…").
    @AppStorage("ganttWeekdayColors") private var weekdayColorsRaw = ""

    private let dayWidth: CGFloat = 26
    private let headerHeight: CGFloat = 56

    private var rowHeight: CGFloat { complexRows ? 64 : 36 }
    private var nameColumnWidth: CGFloat { complexRows ? 250 : 220 }

    struct LinkDraft {
        let fromTask: TodoTask
        let fromPoint: CGPoint
        var currentPoint: CGPoint
    }

    var body: some View {
        let rows = makeRows()
        let range = dateRange(for: rows)
        let days = dayCount(in: range)
        let totalWidth = CGFloat(days) * dayWidth
        let critical = criticalPathIDs(rows: rows)

        VStack(spacing: 0) {
            ScrollView(.vertical) {
                // G8 — i nomi hanno la loro colonna: i giorni non ci passano
                // sotto, la timeline comincia dopo le scritte.
                HStack(alignment: .top, spacing: 0) {
                    namesColumn(rows: rows)
                        .frame(width: nameColumnWidth, alignment: .topLeading)
                    Divider()
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            GanttHeader(range: range, days: days,
                                        dayWidth: dayWidth, height: headerHeight)
                            Divider()
                            timelineGrid(rows: rows, range: range,
                                         days: days, critical: critical)
                                .frame(width: totalWidth,
                                       height: CGFloat(rows.count) * rowHeight,
                                       alignment: .topLeading)
                        }
                        .frame(width: totalWidth, alignment: .leading)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                legend
            }

            Divider()
            creationBar
        }
        .background(DSColor.surface)
    }

    // MARK: Colonna dei nomi (G8)

    private func namesColumn(rows: [GanttRow]) -> some View {
        VStack(spacing: 0) {
            cornerControls
                .frame(height: headerHeight)
            Divider()
            ForEach(rows) { row in
                nameRow(row)
                    .frame(height: rowHeight)
                    .background {
                        if row.isPhase {
                            tint(for: row).opacity(0.06)
                        }
                    }
            }
            Spacer(minLength: 0)
        }
    }

    /// G10/G15 — i controlli del Gantt nell'angolo: comprimi tutto,
    /// vista semplice/complessa, colori dei giorni.
    private var cornerControls: some View {
        HStack(spacing: DS.s) {
            Text("Attività")
                .font(.dsCaption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                withAnimation(.dsQuick) { toggleCollapseAll() }
            } label: {
                Image(systemName: allCollapsed
                      ? "arrow.up.left.and.arrow.down.right"
                      : "arrow.down.right.and.arrow.up.left")
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(allCollapsed ? "Espandi tutto" : "Comprimi tutto")

            Button {
                withAnimation(.dsQuick) { complexRows.toggle() }
            } label: {
                Image(systemName: complexRows
                      ? "rectangle.compress.vertical"
                      : "rectangle.expand.vertical")
                    .font(.dsCaption)
                    .foregroundStyle(complexRows ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(complexRows ? "Vista semplificata (solo barre)"
                              : "Vista completa (fase, etichetta, progresso)")

            weekdayColorsMenu
        }
        .padding(.horizontal, DS.s)
    }

    /// G15 — lunedì rosso, venerdì verde: ognuno il suo calendario mentale.
    private var weekdayColorsMenu: some View {
        let calendar = Calendar.current
        let symbols = calendar.standaloneWeekdaySymbols  // [dom, lun, …]
        return Menu {
            ForEach(1...7, id: \.self) { weekday in
                Menu(symbols[weekday - 1].capitalized) {
                    Button("Nessun colore") {
                        setWeekdayColor(weekday, hex: nil)
                    }
                    ForEach(DSPalette.swatches) { swatch in
                        Button {
                            setWeekdayColor(weekday, hex: swatch.hex)
                        } label: {
                            Label {
                                Text(swatch.name)
                            } icon: {
                                Image(systemName: weekdayColors[weekday]?.1 == swatch.hex
                                      ? "checkmark.circle.fill" : "circle.fill")
                            }
                        }
                        .tint(swatch.color)
                    }
                }
            }
            if !weekdayColors.isEmpty {
                Divider()
                Button("Rimuovi tutti i colori") {
                    weekdayColorsRaw = ""
                }
            }
        } label: {
            Image(systemName: "paintpalette")
                .font(.dsCaption)
                .foregroundStyle(weekdayColors.isEmpty ? Color.secondary : Color.accentColor)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Colora i giorni della settimana")
    }

    /// weekday (1-7) → (Color, hex).
    private var weekdayColors: [Int: (Color, String)] {
        var result: [Int: (Color, String)] = [:]
        for pair in weekdayColorsRaw.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let day = Int(parts[0]) else { continue }
            let hex = String(parts[1])
            result[day] = (Color(hex: hex), hex)
        }
        return result
    }

    private func setWeekdayColor(_ weekday: Int, hex: String?) {
        var colors = weekdayColors.mapValues(\.1)
        colors[weekday] = hex
        weekdayColorsRaw = colors
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
    }

    private var allCollapsed: Bool {
        let collapsible = collapsibleIDs
        return !collapsible.isEmpty && collapsible.isSubset(of: collapsedRows)
    }

    private var collapsibleIDs: Set<UUID> {
        var ids: Set<UUID> = []
        func visit(_ task: TodoTask) {
            let kids = task.liveSubtasks.filter { !$0.isTemplate }
            if !kids.isEmpty { ids.insert(task.id) }
            for kid in kids { visit(kid) }
        }
        for phase in project.phaseTasks { visit(phase) }
        for task in project.unphasedTasks { visit(task) }
        return ids
    }

    /// G10 — un colpo solo: tutto chiuso (solo elementi principali) o tutto aperto.
    private func toggleCollapseAll() {
        if allCollapsed {
            collapsedRows.removeAll()
        } else {
            collapsedRows = collapsibleIDs
        }
    }

    /// Una riga della colonna nomi: semplice (titolo) o complessa
    /// (titolo+fase / etichetta / progresso) — G10/G14.
    @ViewBuilder
    private func nameRow(_ row: GanttRow) -> some View {
        let indent = CGFloat(row.depth) * 14
        HStack(spacing: DS.xs) {
            if row.hasChildren {
                Button {
                    withAnimation(.dsQuick) {
                        if collapsedRows.contains(row.task.id) {
                            collapsedRows.remove(row.task.id)
                        } else {
                            collapsedRows.insert(row.task.id)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(collapsedRows.contains(row.task.id) ? -90 : 0))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 14, height: 1)
            }

            if complexRows, !row.isPhase {
                complexNameContent(row)
            } else {
                simpleNameContent(row)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, DS.s + indent)
        .padding(.trailing, DS.xs)
        .contentShape(Rectangle())
        .onTapGesture { router.open(taskID: row.task.id) }
        .contextMenu { rowContextMenu(row) }
    }

    @ViewBuilder
    private func simpleNameContent(_ row: GanttRow) -> some View {
        if row.isPhase {
            Circle()
                .fill(tint(for: row))
                .frame(width: 7, height: 7)
        } else if row.task.kind == .shootDay || row.task.kind == .event {
            Image(systemName: row.task.kind.systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint(for: row))
        }
        Text(row.task.title)
            .font(row.isPhase ? .dsCaption.weight(.bold) : .dsCaption)
            .foregroundStyle(row.task.isDone ? .tertiary : (row.isPhase ? .primary : .secondary))
            .strikethrough(row.task.isDone)
            .lineLimit(1)
        if row.hasChildren, collapsedRows.contains(row.task.id) {
            let kids = row.task.liveSubtasks.filter { !$0.isTemplate }
            Text("\(kids.filter(\.isDone).count)/\(kids.count)")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    /// G14 — titolo + fase sulla stessa riga, sotto l'etichetta,
    /// sotto ancora la barra di progresso.
    private func complexNameContent(_ row: GanttRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: DS.xs) {
                if row.task.kind == .shootDay || row.task.kind == .event {
                    Image(systemName: row.task.kind.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint(for: row))
                }
                Text(row.task.title)
                    .font(.dsCaption.weight(.medium))
                    .foregroundStyle(row.task.isDone ? .tertiary : .primary)
                    .strikethrough(row.task.isDone)
                    .lineLimit(1)
                if let phase = row.task.phaseAncestor {
                    Text(phase.title)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            if let tag = row.task.orderedTags.first {
                Text("#\(tag.name)")
                    .font(.system(size: 8.5, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color(hex: tag.colorHex).opacity(0.15), in: Capsule())
                    .foregroundStyle(Color(hex: tag.colorHex))
            }
            ProgressView(value: progress(of: row.task))
                .progressViewStyle(.linear)
                .tint(tint(for: row))
                .frame(maxWidth: 130)
                .scaleEffect(y: 0.8)
        }
        .padding(.vertical, 4)
    }

    /// G9 — il tasto destro lavora: aprire, vincolare, colorare, eliminare.
    @ViewBuilder
    private func rowContextMenu(_ row: GanttRow) -> some View {
        Button {
            router.open(taskID: row.task.id)
        } label: {
            Label("Apri dettagli…", systemImage: "rectangle.expand.vertical")
        }
        Divider()
        TaskMenuContent(task: row.task)
        if row.isPhase {
            phaseColorMenu(row.task)
        }
        Divider()
        dependencyCreateMenu(for: row.task)
        removeDependenciesMenu(for: row.task)
    }

    /// D57 — il colore della fase, anche dal Gantt (G9).
    private func phaseColorMenu(_ phase: TodoTask) -> some View {
        Menu {
            Button("Colore del progetto") {
                phase.colorHex = ""
                phase.touch()
            }
            ForEach(DSPalette.swatches) { swatch in
                Button {
                    phase.colorHex = swatch.hex
                    phase.touch()
                } label: {
                    Label {
                        Text(swatch.name)
                    } icon: {
                        Image(systemName: phase.colorHex == swatch.hex
                              ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
                .tint(swatch.color)
            }
        } label: {
            Label("Colore fase", systemImage: "paintpalette")
        }
    }

    /// G14 — le relazioni si creano anche dal menu, non solo col drag.
    @ViewBuilder
    private func dependencyCreateMenu(for task: TodoTask) -> some View {
        if !task.isPhase {
            let candidates = makeRows()
                .filter { !$0.isPhase && $0.task.id != task.id }
                .prefix(25)
            if !candidates.isEmpty {
                Menu {
                    ForEach(Array(candidates), id: \.task.id) { row in
                        Button(row.task.title) {
                            createDependency(from: task, to: row.task)
                        }
                    }
                } label: {
                    Label("Vincolo verso…", systemImage: "arrow.right.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func removeDependenciesMenu(for task: TodoTask) -> some View {
        let outgoing = allDependencies.filter { $0.fromTaskID == task.id }
        if !outgoing.isEmpty {
            ForEach(outgoing, id: \.id) { dependency in
                Button(role: .destructive) {
                    dependency.deletedAt = .now
                    dependency.updatedAt = .now
                } label: {
                    Label("Rimuovi vincolo → \(title(of: dependency.toTaskID))",
                          systemImage: "xmark.circle")
                }
            }
        }
    }

    private func title(of taskID: UUID) -> String {
        makeRows().first { $0.task.id == taskID }?.task.title ?? "?"
    }

    // MARK: Creazione dalla vista (D41)

    @State private var newItemTitle = ""
    @State private var newItemIsPhase = false

    private var creationBar: some View {
        HStack(spacing: DS.m) {
            Menu {
                Picker("Tipo", selection: $newItemIsPhase) {
                    Label("Attività", systemImage: "checkmark.circle").tag(false)
                    Label("Fase", systemImage: "square.stack.3d.up").tag(true)
                }
            } label: {
                Image(systemName: newItemIsPhase ? "square.stack.3d.up" : "checkmark.circle")
                    .foregroundStyle(Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            TextField(
                "",
                text: $newItemTitle,
                prompt: Text(newItemIsPhase
                             ? "Nuova fase…"
                             : "Nuova attività (parte oggi, 3 giorni)…")
            )
            .labelsHidden()
            .textFieldStyle(.plain)
            .onSubmit { addItem() }

            Button("Aggiungi") { addItem() }
                .disabled(newItemTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .font(.dsMeta)
        .padding(DS.m)
    }

    private func addItem(startingAt day: Date? = nil) {
        let title = newItemTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        createItem(title: title, isPhase: newItemIsPhase, startingAt: day)
        newItemTitle = ""
    }

    @discardableResult
    private func createItem(title: String, isPhase: Bool, startingAt day: Date?) -> TodoTask {
        let task = TodoTask(
            workspaceID: project.workspaceID,
            title: title,
            kind: isPhase ? .phase : .task,
            sortOrder: (project.phaseTasks.map(\.sortOrder).max() ?? -1) + 1,
            createdByID: project.createdByID
        )
        if !isPhase {
            let start = (day ?? .now).startOfDay
            task.startAt = start
            task.dueAt = Calendar.current.date(byAdding: .day, value: 2, to: start)
        }
        modelContext.insert(task)
        task.project = project
        return task
    }

    // MARK: Grid

    @ViewBuilder
    private func timelineGrid(
        rows: [GanttRow], range: ClosedRange<Date>, days: Int, critical: Set<UUID>
    ) -> some View {
        ZStack(alignment: .topLeading) {
            GanttGridBackground(
                range: range, days: days, rowCount: rows.count,
                dayWidth: dayWidth, rowHeight: rowHeight,
                weekdayColors: weekdayColors.mapValues(\.0)
            )
            // G9 — doppio click sul vuoto: nuova attività in quel giorno;
            // tasto destro: creazione rapida.
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        let day = Calendar.current.date(
                            byAdding: .day,
                            value: Int(value.location.x / dayWidth),
                            to: range.lowerBound
                        ) ?? .now
                        let task = createItem(title: "Nuova attività",
                                              isPhase: false, startingAt: day)
                        router.open(taskID: task.id)
                    }
            )
            .contextMenu {
                Button {
                    let task = createItem(title: "Nuova attività",
                                          isPhase: false, startingAt: .now)
                    router.open(taskID: task.id)
                } label: {
                    Label("Nuova attività (oggi)", systemImage: "plus.circle")
                }
                Button {
                    createItem(title: "Nuova fase", isPhase: true, startingAt: nil)
                } label: {
                    Label("Nuova fase", systemImage: "square.stack.3d.up")
                }
                Text("Doppio click su un giorno: attività in quella data")
            }

            // F38 — la fascia della fase raggruppa visivamente le sue righe.
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if row.isPhase {
                    tint(for: row)
                        .opacity(0.06)
                        .frame(height: rowHeight)
                        .offset(y: CGFloat(index) * rowHeight)
                        .allowsHitTesting(false)
                }
            }

            // Dependency arrows under the bars.
            GanttArrowsCanvas(
                dependencies: projectDependencies(rows: rows),
                linkDraft: linkDraft,
                criticalIDs: critical,
                barFrame: { barFrame(for: $0, rows: rows, range: range) }
            )

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                GanttBarRow(
                    row: row,
                    frame: barFrame(for: row.task.id, rows: rows, range: range),
                    dayWidth: dayWidth,
                    rowHeight: rowHeight,
                    tint: tint(for: row),
                    isCritical: critical.contains(row.task.id),
                    progress: progress(of: row.task),
                    assigneeInitials: row.isPhase ? nil : assigneeInitials(for: row.task),
                    contextMenu: { AnyView(rowContextMenu(row)) },
                    onMoveDays: { shift(row.task, byDays: $0) },
                    onResizeEndDays: { resize(row.task, byDays: $0) },
                    onResizeStartDays: { resizeStart(row.task, byDays: $0) },
                    onLinkDrag: { point, start in
                        if linkDraft == nil {
                            linkDraft = LinkDraft(fromTask: row.task,
                                                  fromPoint: start, currentPoint: point)
                        } else {
                            linkDraft?.currentPoint = point
                        }
                    },
                    onLinkEnd: { point in
                        defer { linkDraft = nil }
                        createDependency(from: row.task, at: point, rows: rows)
                    },
                    onOpen: { router.open(taskID: row.task.id) }
                )
                .offset(y: CGFloat(index) * rowHeight)
            }
        }
        .coordinateSpace(name: "ganttGrid")
    }

    private var legend: some View {
        HStack(spacing: DS.m) {
            Label("Trascina per spostare", systemImage: "arrow.left.and.right")
            Label("Maniglie: durata", systemImage: "arrow.right.to.line")
            Label("Cerchio: vincolo", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            Label("Doppio click sul vuoto: crea", systemImage: "plus.circle")
        }
        .font(.dsCaption)
        .foregroundStyle(.secondary)
        .padding(DS.s)
        .background(.thinMaterial, in: Capsule())
        .padding(DS.m)
    }

    // MARK: Rows & geometry

    /// Una riga del Gantt: fase o attività, con profondità (gerarchia G14).
    struct GanttRow: Identifiable {
        let task: TodoTask
        let depth: Int
        let isPhase: Bool
        let hasChildren: Bool

        var id: UUID { task.id }
    }

    private func makeRows() -> [GanttRow] {
        var result: [GanttRow] = []

        func appendChildren(of task: TodoTask, depth: Int) {
            let children = task.liveSubtasks
                .filter { !$0.isTemplate && !$0.isPhase }
                .sorted { $0.sortOrder < $1.sortOrder }
            for child in children {
                let kids = child.liveSubtasks.filter { !$0.isTemplate }
                result.append(GanttRow(task: child, depth: depth,
                                       isPhase: false, hasChildren: !kids.isEmpty))
                if !kids.isEmpty, !collapsedRows.contains(child.id) {
                    appendChildren(of: child, depth: depth + 1)
                }
            }
        }

        for phase in project.phaseTasks {
            let kids = phase.liveSubtasks.filter { !$0.isTemplate && !$0.isPhase }
            result.append(GanttRow(task: phase, depth: 0,
                                   isPhase: true, hasChildren: !kids.isEmpty))
            if !collapsedRows.contains(phase.id) {
                appendChildren(of: phase, depth: 1)
            }
        }
        for task in project.unphasedTasks {
            let kids = task.liveSubtasks.filter { !$0.isTemplate }
            result.append(GanttRow(task: task, depth: 0,
                                   isPhase: false, hasChildren: !kids.isEmpty))
            if !kids.isEmpty, !collapsedRows.contains(task.id) {
                appendChildren(of: task, depth: 1)
            }
        }
        return result
    }

    /// G14 — progresso: figli completati, o fatto/non fatto senza figli.
    private func progress(of task: TodoTask) -> Double {
        if task.isPhase { return task.aggregatedProgress }
        if task.isDone { return 1 }
        let children = task.liveSubtasks.filter { !$0.isTemplate }
        guard !children.isEmpty else { return 0 }
        return Double(children.filter(\.isDone).count) / Double(children.count)
    }

    /// Le iniziali dell'assegnatario, per le barre (F38).
    private func assigneeInitials(for task: TodoTask) -> String? {
        guard let id = task.assigneeID,
              let person = people.first(where: { $0.id == id })
        else { return nil }
        let parts = person.name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    private func dateRange(for rows: [GanttRow]) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let today = Date.now.startOfDay
        let spans = rows.compactMap { barSpan(for: $0) }
        let minDate = spans.map(\.start).min() ?? today
        let maxDate = spans.map(\.end).max() ?? calendar.date(byAdding: .day, value: 21, to: today)!
        let lower = calendar.date(byAdding: .day, value: -7, to: min(minDate, today))!
        let upper = calendar.date(byAdding: .day, value: 14, to: max(maxDate, today))!
        return lower...upper
    }

    private func dayCount(in range: ClosedRange<Date>) -> Int {
        (Calendar.current.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 30) + 1
    }

    /// The dated span a bar covers: explicit dates for tasks, the children's
    /// envelope for phases and for collapsed parents (G14).
    private func barSpan(for row: GanttRow) -> (start: Date, end: Date)? {
        if row.isPhase || (row.hasChildren && collapsedRows.contains(row.task.id)) {
            let children = row.task.liveSubtasks.filter { !$0.isTemplate }
            let spans = children.compactMap { taskSpan($0) }
            guard let start = spans.map(\.start).min(), let end = spans.map(\.end).max()
            else { return taskSpan(row.task) }
            if let own = taskSpan(row.task), !row.isPhase {
                return (min(start, own.start), max(end, own.end))
            }
            return (start, end)
        }
        return taskSpan(row.task)
    }

    private func taskSpan(_ task: TodoTask) -> (start: Date, end: Date)? {
        let start = task.startAt ?? task.dueAt
        let end = task.endAt ?? task.dueAt ?? task.startAt
        guard let start, let end else { return nil }
        return (min(start, end).startOfDay, max(start, end).startOfDay)
    }

    private func barFrame(for taskID: UUID, rows: [GanttRow], range: ClosedRange<Date>) -> CGRect? {
        guard let index = rows.firstIndex(where: { $0.task.id == taskID }),
              let span = barSpan(for: rows[index])
        else { return nil }
        let calendar = Calendar.current
        let startDays = calendar.dateComponents([.day], from: range.lowerBound, to: span.start).day ?? 0
        let lengthDays = (calendar.dateComponents([.day], from: span.start, to: span.end).day ?? 0) + 1
        let barHeight: CGFloat = rows[index].isPhase ? 10 : (complexRows ? 26 : 20)
        return CGRect(
            x: CGFloat(startDays) * dayWidth,
            y: CGFloat(index) * rowHeight + (rowHeight - barHeight) / 2,
            width: CGFloat(lengthDays) * dayWidth,
            height: barHeight
        )
    }

    private func projectDependencies(rows: [GanttRow]) -> [TaskDependency] {
        let ids = Set(rows.map(\.task.id))
        return allDependencies.filter { ids.contains($0.fromTaskID) && ids.contains($0.toTaskID) }
    }

    // MARK: Critical path (D37)

    /// Longest finish-to-start chain by duration across the dependency DAG.
    /// Only chains with at least one constraint count — a lone long task is
    /// not a "path".
    private func criticalPathIDs(rows: [GanttRow]) -> Set<UUID> {
        let dependencies = projectDependencies(rows: rows)
        guard !dependencies.isEmpty else { return [] }

        var durations: [UUID: Int] = [:]
        for row in rows where !row.isPhase && !row.task.isDone {
            guard let span = taskSpan(row.task) else { continue }
            let days = (Calendar.current.dateComponents([.day], from: span.start, to: span.end).day ?? 0) + 1
            durations[row.task.id] = days
        }

        var successors: [UUID: [UUID]] = [:]
        for dependency in dependencies {
            successors[dependency.fromTaskID, default: []].append(dependency.toTaskID)
        }

        // Memoized longest path from each node; visiting-set guards cycles.
        var memo: [UUID: (length: Int, path: [UUID])] = [:]
        var visiting = Set<UUID>()

        func longest(from id: UUID) -> (length: Int, path: [UUID]) {
            if let cached = memo[id] { return cached }
            guard !visiting.contains(id), let duration = durations[id] else { return (0, []) }
            visiting.insert(id)
            defer { visiting.remove(id) }
            var best: (length: Int, path: [UUID]) = (duration, [id])
            for next in successors[id] ?? [] {
                let tail = longest(from: next)
                if tail.length + duration > best.length {
                    best = (tail.length + duration, [id] + tail.path)
                }
            }
            memo[id] = best
            return best
        }

        var bestPath: [UUID] = []
        var bestLength = 0
        for id in durations.keys {
            let candidate = longest(from: id)
            if candidate.length > bestLength, candidate.path.count > 1 {
                bestLength = candidate.length
                bestPath = candidate.path
            }
        }
        return Set(bestPath)
    }

    // MARK: Mutations

    /// D57 al lavoro anche qui: la fase colorata tinge le sue barre.
    private func tint(for row: GanttRow) -> Color {
        let phase = row.isPhase ? row.task : row.task.phaseAncestor
        if let hex = phase?.colorHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        return Color(hex: project.colorHex)
    }

    private func shift(_ task: TodoTask, byDays days: Int) {
        guard days != 0 else { return }
        let calendar = Calendar.current
        func moved(_ date: Date?) -> Date? {
            date.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
        }
        if task.isPhase || !task.liveSubtasks.isEmpty {
            // Moving a parent moves its whole subtree.
            for child in task.liveSubtasks {
                shift(child, byDays: days)
            }
        }
        task.startAt = moved(task.startAt)
        task.endAt = moved(task.endAt)
        task.dueAt = moved(task.dueAt)
        task.remindAt = moved(task.remindAt)
        task.touch()
    }

    private func resize(_ task: TodoTask, byDays days: Int) {
        guard days != 0, !task.isPhase else { return }
        let calendar = Calendar.current
        guard let span = taskSpan(task) else { return }
        let newEnd = calendar.date(byAdding: .day, value: days, to: span.end) ?? span.end
        let clampedEnd = max(newEnd, span.start)
        if task.endAt != nil {
            task.endAt = clampedEnd
        } else {
            task.dueAt = clampedEnd
        }
        task.touch()
    }

    /// G14 — la maniglia sinistra sposta l'INIZIO (la fine resta ferma).
    private func resizeStart(_ task: TodoTask, byDays days: Int) {
        guard days != 0, !task.isPhase else { return }
        let calendar = Calendar.current
        guard let span = taskSpan(task) else { return }
        let newStart = calendar.date(byAdding: .day, value: days, to: span.start) ?? span.start
        task.startAt = min(newStart, span.end)
        task.touch()
    }

    private func createDependency(from task: TodoTask, at point: CGPoint, rows: [GanttRow]) {
        let index = Int(point.y / rowHeight)
        guard rows.indices.contains(index) else { return }
        let target = rows[index].task
        guard !rows[index].isPhase else { return }
        createDependency(from: task, to: target)
    }

    private func createDependency(from task: TodoTask, to target: TodoTask) {
        guard target.id != task.id, !task.isPhase else { return }
        let exists = allDependencies.contains {
            ($0.fromTaskID == task.id && $0.toTaskID == target.id)
                || ($0.fromTaskID == target.id && $0.toTaskID == task.id)
        }
        guard !exists else { return }
        let dependency = TaskDependency(
            workspaceID: project.workspaceID,
            fromTaskID: task.id,
            toTaskID: target.id
        )
        modelContext.insert(dependency)
    }
}

// MARK: - Header

/// F38 — header a DUE livelli (pattern TeamGantt/Vikunja): la fascia dei
/// mesi sopra, i giorni con l'iniziale del giorno della settimana sotto.
private struct GanttHeader: View {
    let range: ClosedRange<Date>
    let days: Int
    let dayWidth: CGFloat
    let height: CGFloat

    private struct MonthBand: Identifiable {
        let id: Int
        let label: String
        let dayCount: Int
    }

    private var monthBands: [MonthBand] {
        let calendar = Calendar.current
        var bands: [MonthBand] = []
        var offset = 0
        while offset < days {
            let day = calendar.date(byAdding: .day, value: offset, to: range.lowerBound)!
            let monthEnd = calendar.dateInterval(of: .month, for: day)!.end
            let remaining = calendar.dateComponents([.day], from: day, to: monthEnd).day ?? 1
            let span = min(remaining, days - offset)
            bands.append(MonthBand(
                id: offset,
                label: day.formatted(.dateTime.month(.wide).year()).capitalized,
                dayCount: max(span, 1)
            ))
            offset += max(span, 1)
        }
        return bands
    }

    var body: some View {
        let calendar = Calendar.current
        VStack(spacing: 0) {
            // Fascia dei mesi. G11 — il confine di mese è ben marcato.
            HStack(spacing: 0) {
                ForEach(monthBands) { band in
                    Text(band.label)
                        .font(.dsCaption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: CGFloat(band.dayCount) * dayWidth, alignment: .leading)
                        .padding(.leading, band.dayCount > 2 ? DS.xs : 0)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.3))
                                .frame(width: 1.5)
                        }
                }
            }
            .padding(.vertical, 3)

            // Giorni: iniziale + numero, oggi in pill.
            HStack(spacing: 0) {
                ForEach(0..<days, id: \.self) { offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: range.lowerBound)!
                    let isWeekend = calendar.isDateInWeekend(day)
                    VStack(spacing: 1) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(isWeekend ? .tertiary : .secondary)
                        Text("\(calendar.component(.day, from: day))")
                            .font(.dsNumeric)
                            .foregroundStyle(
                                day.isToday ? Color.white
                                : isWeekend ? Color.secondary : .primary
                            )
                            .frame(width: 20, height: 20)
                            .background {
                                if day.isToday {
                                    Circle().fill(Color.accentColor)
                                }
                            }
                    }
                    .frame(width: dayWidth)
                }
            }
            .padding(.bottom, DS.xs)
        }
        .frame(height: height)
    }
}

// MARK: - Background grid

private struct GanttGridBackground: View {
    let range: ClosedRange<Date>
    let days: Int
    let rowCount: Int
    let dayWidth: CGFloat
    let rowHeight: CGFloat
    /// G15 — weekday (1-7) → colore di fondo del giorno.
    var weekdayColors: [Int: Color] = [:]

    var body: some View {
        Canvas { context, size in
            let calendar = Calendar.current
            for offset in 0..<days {
                let day = calendar.date(byAdding: .day, value: offset, to: range.lowerBound)!
                let x = CGFloat(offset) * dayWidth
                // G15 — il colore scelto per quel giorno della settimana.
                if let custom = weekdayColors[calendar.component(.weekday, from: day)] {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: dayWidth, height: size.height)),
                        with: .color(custom.opacity(0.10))
                    )
                } else if calendar.isDateInWeekend(day) {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: dayWidth, height: size.height)),
                        with: .color(Color.primary.opacity(0.035))
                    )
                }
                if day.isToday {
                    context.fill(
                        Path(CGRect(x: x, y: 0, width: dayWidth, height: size.height)),
                        with: .color(Color.accentColor.opacity(0.07))
                    )
                }
                // G11 — cambio mese ben visibile > inizio settimana > giorno.
                let isMonthStart = calendar.component(.day, from: day) == 1
                let isWeekStart = calendar.component(.weekday, from: day)
                    == calendar.firstWeekday
                context.stroke(
                    Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                    with: .color(Color.primary.opacity(
                        isMonthStart ? 0.3 : isWeekStart ? 0.12 : 0.05
                    )),
                    lineWidth: isMonthStart ? 1.5 : 1
                )
            }
            for rowIndex in 0...rowCount {
                let y = CGFloat(rowIndex) * rowHeight
                context.stroke(
                    Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                    with: .color(Color.primary.opacity(0.04)),
                    lineWidth: 1
                )
            }
        }
    }
}

// MARK: - Dependency arrows

private struct GanttArrowsCanvas: View {
    let dependencies: [TaskDependency]
    let linkDraft: ProjectGanttView.LinkDraft?
    let criticalIDs: Set<UUID>
    let barFrame: (UUID) -> CGRect?

    var body: some View {
        Canvas { context, _ in
            for dependency in dependencies {
                guard let from = barFrame(dependency.fromTaskID),
                      let to = barFrame(dependency.toTaskID)
                else { continue }
                // Critical edges burn red (D37).
                let isCritical = criticalIDs.contains(dependency.fromTaskID)
                    && criticalIDs.contains(dependency.toTaskID)
                drawArrow(
                    in: &context,
                    from: CGPoint(x: from.maxX, y: from.midY),
                    to: CGPoint(x: to.minX, y: to.midY),
                    color: isCritical ? DSColor.overdue : .secondary,
                    lineWidth: isCritical ? 2.2 : 1.5
                )
            }
            if let draft = linkDraft {
                var path = Path()
                path.move(to: draft.fromPoint)
                path.addLine(to: draft.currentPoint)
                context.stroke(
                    path,
                    with: .color(Color.accentColor),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func drawArrow(
        in context: inout GraphicsContext, from: CGPoint, to: CGPoint,
        color: Color, lineWidth: CGFloat = 1.5
    ) {
        let gap: CGFloat = 8
        var path = Path()
        path.move(to: from)
        path.addLine(to: CGPoint(x: from.x + gap, y: from.y))
        path.addLine(to: CGPoint(x: from.x + gap, y: to.y))
        path.addLine(to: CGPoint(x: to.x - 3, y: to.y))
        context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: lineWidth)

        var head = Path()
        head.move(to: CGPoint(x: to.x - 7, y: to.y - 4))
        head.addLine(to: CGPoint(x: to.x - 1, y: to.y))
        head.addLine(to: CGPoint(x: to.x - 7, y: to.y + 4))
        head.closeSubpath()
        context.fill(head, with: .color(color.opacity(0.6)))
    }
}

// MARK: - Bar row

private struct GanttBarRow: View {
    let row: ProjectGanttView.GanttRow
    let frame: CGRect?
    let dayWidth: CGFloat
    let rowHeight: CGFloat
    let tint: Color
    let isCritical: Bool
    /// G14 — quota di completamento: riempie la barra.
    let progress: Double
    let assigneeInitials: String?
    let contextMenu: () -> AnyView
    let onMoveDays: (Int) -> Void
    let onResizeEndDays: (Int) -> Void
    let onResizeStartDays: (Int) -> Void
    let onLinkDrag: (CGPoint, CGPoint) -> Void
    let onLinkEnd: (CGPoint) -> Void
    let onOpen: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var resizeEndOffset: CGFloat = 0
    @State private var resizeStartOffset: CGFloat = 0
    @State private var isHoveringBar = false

    var body: some View {
        if let frame {
            bar(frame)
        }
        // Senza date la riga vive solo nella colonna nomi (G8).
    }

    @ViewBuilder
    private func bar(_ frame: CGRect) -> some View {
        let width = max(frame.width + resizeEndOffset - resizeStartOffset, dayWidth)
        let shape = RoundedRectangle(cornerRadius: row.isPhase ? 4 : 7)
        let fillColor = isCritical ? DSColor.overdue : tint

        shape
            // G14 — la barra È la percentuale: 15% di colore per il
            // pianificato, colore pieno per il completato.
            .fill(fillColor.opacity(0.15))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    shape.fill(fillColor.opacity(row.task.isDone ? 0.55 : 1))
                        .frame(width: max(proxy.size.width * progress, 0))
                }
            }
            .overlay {
                if !row.isPhase {
                    insideLabel
                }
            }
            .overlay {
                shape.strokeBorder(fillColor.opacity(0.35))
            }
            // G14 — due maniglie piccole ed eleganti: la durata si vede.
            .overlay(alignment: .leading) {
                if row.isPhase {
                    phaseDiamond.offset(x: -4)
                } else {
                    resizeHandle
                        .gesture(resizeStartGesture)
                        .offset(x: 2)
                }
            }
            .overlay(alignment: .trailing) {
                if row.isPhase {
                    phaseDiamond.offset(x: 4)
                } else {
                    resizeHandle
                        .gesture(resizeEndGesture)
                        .offset(x: -2)
                }
            }
            .overlay(alignment: .trailing) {
                if !row.isPhase {
                    linkHandle(frame)
                }
            }
            .frame(width: width, height: frame.height)
            .gesture(moveGesture)
            .onTapGesture(perform: onOpen)
            #if os(macOS)
            .onHover { isHoveringBar = $0 }
            #endif
            .contextMenu { contextMenu() }
            .offset(x: frame.minX + dragOffset + resizeStartOffset, y: frame.minY)
            .animation(.dsQuick, value: frame)
    }

    private var phaseDiamond: some View {
        Rectangle()
            .fill(tint)
            .frame(width: 8, height: 8)
            .rotationEffect(.degrees(45))
    }

    /// G14 — il titolo vive nella barra: se non entra, puntini sospensivi.
    private var insideLabel: some View {
        HStack(spacing: DS.xs) {
            Text(row.task.title)
                .font(.system(size: 10, weight: .semibold))
                .strikethrough(row.task.isDone)
                .lineLimit(1)
                .truncationMode(.tail)
                // Sul riempimento pieno il testo è bianco, sul 15% scuro.
                .foregroundStyle(progress > 0.45 ? Color.white : tint)
            Spacer(minLength: 0)
            if let assigneeInitials {
                Text(assigneeInitials)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(tint.opacity(0.8), in: Circle())
            }
        }
        .padding(.horizontal, 8)
        .allowsHitTesting(false)
    }

    /// La maniglia di durata: una capsula sottile, visibile all'hover.
    private var resizeHandle: some View {
        Capsule()
            .fill(tint.opacity(isHoveringBar ? 0.9 : 0.45))
            .frame(width: 3, height: 12)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            #if os(macOS)
            .pointerStyle(.frameResize(position: .trailing))
            #endif
            .animation(.dsQuick, value: isHoveringBar)
    }

    /// F38 — la maniglia dei vincoli: sul bordo, cresce all'hover, il suo
    /// drag ha priorità sul movimento della barra.
    private func linkHandle(_ frame: CGRect) -> some View {
        Circle()
            .strokeBorder(Color.accentColor, lineWidth: 1.5)
            .background(Circle().fill(DSColor.surface))
            .frame(width: isHoveringBar ? 13 : 9, height: isHoveringBar ? 13 : 9)
            .offset(x: 14)
            .contentShape(Circle().inset(by: -10))
            .highPriorityGesture(linkGesture(frame))
            .opacity(isHoveringBar ? 1 : 0.55)
            .animation(.dsQuick, value: isHoveringBar)
            .help("Trascina su un'altra barra per creare un vincolo")
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                let days = Int((value.translation.width / dayWidth).rounded())
                dragOffset = 0
                onMoveDays(days)
            }
    }

    private var resizeEndGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                resizeEndOffset = value.translation.width
            }
            .onEnded { value in
                let days = Int((value.translation.width / dayWidth).rounded())
                resizeEndOffset = 0
                onResizeEndDays(days)
            }
    }

    private var resizeStartGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                resizeStartOffset = value.translation.width
            }
            .onEnded { value in
                let days = Int((value.translation.width / dayWidth).rounded())
                resizeStartOffset = 0
                onResizeStartDays(days)
            }
    }

    private func linkGesture(_ frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("ganttGrid"))
            .onChanged { value in
                onLinkDrag(value.location, CGPoint(x: frame.maxX + 8, y: frame.midY))
            }
            .onEnded { value in
                onLinkEnd(value.location)
            }
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return ProjectGanttView(project: preview.project)
        .modelContainer(preview.container)
}
