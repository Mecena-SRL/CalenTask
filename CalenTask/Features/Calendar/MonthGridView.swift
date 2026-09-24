import SwiftUI
import SwiftData

/// Month grid (rivista in F24/F25; operativa in v8): griglia con bordi, weekend
/// tinteggiato, chip-evento nelle celle quando c'è spazio (Mac/iPad), pallini
/// compatti su iPhone. La heatmap NON spegne più i pallini (F25).
/// Operatività (come Giorno/Settimana): **trascina** un evento su un altro
/// giorno per ri-datarlo; **doppio-tap** su una cella crea lì e apre l'editor.
struct MonthGridView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    let month: Date
    @Binding var selectedDay: Date
    /// Tasks grouped by start-of-day (both startAt and dueAt facets).
    let tasksByDay: [Date: [TodoTask]]
    /// E10 — heatmap densità alla Timepage: celle tinte dal carico del giorno.
    var showsHeatmap = false
    /// F24 — celle ricche con i titoli degli eventi (larghezza permettendo).
    var showsEventChips = false

    /// La cella sotto un trascinamento in corso: bordo accent come bersaglio.
    @State private var dropTargetDay: Date?

    private let calendar = Calendar.app

    var body: some View {
        VStack(spacing: showsEventChips ? 0 : DS.s) {
            HStack(spacing: 0) {
                ForEach(Array(CalendarMath.orderedWeekdaySymbols(calendar: calendar).enumerated()),
                        id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.dsCaption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, showsEventChips ? DS.xs : 0)

            if showsEventChips {
                richGrid
            } else {
                compactGrid
            }
        }
    }

    // MARK: Compatta (iPhone)

    private var compactGrid: some View {
        ForEach(Array(CalendarMath.monthGrid(for: month, calendar: calendar).enumerated()),
                id: \.offset) { _, week in
            HStack(spacing: 0) {
                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                    compactDayCell(day)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func compactDayCell(_ day: Date) -> some View {
        let isCurrentMonth = CalendarMath.isSameMonth(day, month, calendar: calendar)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let dayTasks = tasksByDay[calendar.startOfDay(for: day)] ?? []

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: DS.xs) {
                // E10: oggi è SEMPRE la pill accent piena; la selezione è l'anello.
                Text("\(calendar.component(.day, from: day))")
                    .font(.dsNumeric)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(
                        isToday ? Color.white
                        : isCurrentMonth ? Color.primary : Color.secondary.opacity(0.4)
                    )
                    .frame(width: 32, height: 32)
                    .background {
                        if isToday {
                            Circle().fill(Color.accentColor)
                        } else if isSelected {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }

                // F25 — i pallini restano anche con la heatmap.
                HStack(spacing: 3) {
                    ForEach(Array(dayTasks.prefix(3).enumerated()), id: \.offset) { _, task in
                        Circle()
                            .fill(dotColor(for: task))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity)
            .background {
                if showsHeatmap, isCurrentMonth, !dayTasks.isEmpty {
                    RoundedRectangle(cornerRadius: DS.Radius.small)
                        .fill(Color.accentColor.opacity(heatOpacity(dayTasks.count)))
                        .padding(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Ricca (Mac/iPad, F24)

    private var richGrid: some View {
        VStack(spacing: 0) {
            ForEach(Array(CalendarMath.monthGrid(for: month, calendar: calendar).enumerated()),
                    id: \.offset) { weekIndex, week in
                if weekIndex == 0 { Divider() }
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { dayIndex, day in
                        if dayIndex == 0 { Divider() }
                        richDayCell(day)
                            .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
                        Divider()
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Divider()
            }
        }
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.medium)
                .strokeBorder(DSColor.hairline)
        }
    }

    private func richDayCell(_ day: Date) -> some View {
        let isCurrentMonth = CalendarMath.isSameMonth(day, month, calendar: calendar)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let isWeekend = calendar.isDateInWeekend(day)
        let dayTasks = sortedTasks(on: day)

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Spacer()
                Text("\(calendar.component(.day, from: day))")
                    .font(.dsNumeric.weight(isToday ? .bold : .regular))
                    .foregroundStyle(
                        isToday ? Color.white
                        : isCurrentMonth ? Color.primary : Color.secondary.opacity(0.4)
                    )
                    .frame(width: 22, height: 22)
                    .background {
                        if isToday {
                            Circle().fill(Color.accentColor)
                        } else if isSelected {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }
            }

            ForEach(dayTasks.prefix(3), id: \.id) { task in
                eventChip(task)
            }
            if dayTasks.count > 3 {
                Text("+\(dayTasks.count - 3) altri")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .background {
            if showsHeatmap, isCurrentMonth, !dayTasks.isEmpty {
                Color.accentColor.opacity(heatOpacity(dayTasks.count))
            } else if isWeekend {
                Color.primary.opacity(0.025)
            }
        }
        .overlay {
            // Bersaglio del trascinamento: cornice accent quando ci si rilascia.
            if calendar.isDate(dropTargetDay ?? .distantPast, inSameDayAs: day) {
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(
                        Color.accentColor.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: DS.Radius.small)
                    )
            }
        }
        .contentShape(Rectangle())
        // Doppio-tap crea su questo giorno (come Giorno/Settimana); singolo
        // seleziona (il dettaglio sotto mostra l'intera giornata, anche "+N").
        .onTapGesture(count: 2) { createTask(on: day) }
        .onTapGesture { selectedDay = day }
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            return reschedule(first, to: day)
        } isTargeted: { targeted in
            if targeted {
                dropTargetDay = day
            } else if calendar.isDate(dropTargetDay ?? .distantPast, inSameDayAs: day) {
                dropTargetDay = nil
            }
        }
        .opacity(isCurrentMonth ? 1 : 0.55)
    }

    private func eventChip(_ task: TodoTask) -> some View {
        TaskOpenLink(task: task) {
            HStack(spacing: 3) {
                if let startAt = task.startAt,
                   calendar.isDate(startAt, inSameDayAs: task.dueAt ?? startAt) || task.dueAt == nil {
                    Text(startAt.dsTimeLabel)
                        .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                        .opacity(0.8)
                }
                Text(task.title)
                    .font(.system(size: 9, weight: .medium))
                    .strikethrough(task.isDone)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(dotColor(for: task).opacity(task.isDone ? 0.08 : 0.15),
                        in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(dotColor(for: task).opacity(task.isDone ? 0.6 : 1))
            .contentShape(Rectangle())
        }
        // Trascina la chip su un altro giorno per ri-datare l'attività.
        .draggable(task.id.uuidString)
        .taskContextMenu(task)
    }

    private func sortedTasks(on day: Date) -> [TodoTask] {
        (tasksByDay[calendar.startOfDay(for: day)] ?? [])
            .sorted {
                ($0.startAt ?? $0.dueAt ?? .distantFuture, $1.priorityRaw)
                    < ($1.startAt ?? $1.dueAt ?? .distantFuture, $0.priorityRaw)
            }
    }

    // MARK: Operatività (drag → ri-data, doppio-tap → crea)

    /// Sposta un'attività sul `day` di destinazione preservando l'ora: calcola
    /// lo scarto in giorni dall'ancora (startAt, o la scadenza) e trasla
    /// start/end/due di quei giorni. Il funnel `touch()` ri-sincronizza le
    /// notifiche.
    private func reschedule(_ idString: String, to day: Date) -> Bool {
        guard let id = UUID(uuidString: idString),
              let task = try? modelContext.fetch(
                FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })
              ).first,
              let anchor = task.startAt ?? task.dueAt
        else { return false }

        let deltaDays = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: anchor),
            to: calendar.startOfDay(for: day)
        ).day ?? 0
        guard deltaDays != 0 else { return false }

        withAnimation(.dsQuick) {
            if let start = task.startAt {
                task.startAt = calendar.date(byAdding: .day, value: deltaDays, to: start)
            }
            if let end = task.endAt {
                task.endAt = calendar.date(byAdding: .day, value: deltaDays, to: end)
            }
            if let due = task.dueAt {
                task.dueAt = calendar.date(byAdding: .day, value: deltaDays, to: due)
            }
            task.touch()
            selectedDay = day
        }
        return true
    }

    /// Crea un'attività su `day` e apre subito l'editor (i dettagli si mettono
    /// lì). Nel mese non c'è un'ora: parte come evento alle 9:00 di 1h,
    /// modificabile. Su iPhone la creazione resta dal "+" in toolbar.
    private func createTask(on day: Date) {
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        do {
            let (workspace, me) = try SeedService.ensureSeed(in: modelContext)
            let target = WorkspaceScope.creationTarget(in: modelContext, fallback: workspace)
            let task = TodoTask(
                workspaceID: target.id,
                title: "Nuova attività",
                kind: .task,
                startAt: start,
                endAt: start.addingTimeInterval(3600),
                createdByID: me.id
            )
            modelContext.insert(task)
            try? modelContext.save()
            NotificationService.shared.sync(task: task)
            selectedDay = day
            #if os(macOS)
            router.inspect(taskID: task.id)
            #else
            router.open(taskID: task.id)
            #endif
        } catch {
            assertionFailure("create month task: \(error)")
        }
    }

    private func heatOpacity(_ count: Int) -> Double {
        switch count {
        case 0: 0
        case 1: 0.08
        case 2: 0.15
        case 3: 0.24
        default: 0.34
        }
    }

    private func dotColor(for task: TodoTask) -> Color {
        if let project = task.project {
            return Color(hex: project.colorHex)
        }
        return .accentColor
    }
}
