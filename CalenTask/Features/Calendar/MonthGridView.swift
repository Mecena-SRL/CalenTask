import SwiftUI
import SwiftData

/// Il Mese (rivisto in F24/F25, v8; ridisegnato in fase 2).
///
/// **Ricco** (Mac/iPad): righe elastiche che riempiono l'altezza disponibile,
/// eventi su più giorni come **barre continue** (`CalendarWeekLayout`), eventi
/// con orario come riga pallino·ora·titolo, scadenze con la bandierina; quante
/// righe si vedono dipende dall'altezza della cella, il resto è "+N".
/// **Compatto** (iPhone): numeri con pallini, heatmap opzionale.
///
/// Operatività: **trascina** un elemento su un altro giorno per ri-datarlo;
/// **doppio clic/tap** su una cella crea lì e apre l'editor. La selezione
/// scivola da un giorno all'altro (`matchedGeometryEffect`).
struct MonthGridView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    let month: Date
    @Binding var selectedDay: Date
    /// Tasks grouped by start-of-day (both startAt and dueAt facets).
    let tasksByDay: [Date: [TodoTask]]
    /// E10 — heatmap densità alla Timepage: celle tinte dal carico del giorno.
    var showsHeatmap = false
    /// F24 — celle ricche con barre ed eventi (larghezza permettendo).
    var showsEventChips = false
    /// Numero della settimana a sinistra di ogni riga (celle ricche).
    var showsWeekNumbers = false
    /// Le righe si allungano fino a riempire l'altezza disponibile.
    var fillsHeight = false

    @Namespace private var selectionNamespace
    @State private var gridHeight: CGFloat = 0

    private let calendar = Calendar.app

    // Misure delle celle ricche.
    private let weekNumberWidth: CGFloat = 26
    private let dayNumberHeight: CGFloat = 28
    private let laneHeight: CGFloat = 17
    private let laneGap: CGFloat = 2
    private let fixedRowHeight: CGFloat = 108
    private let minimumRowHeight: CGFloat = 70

    /// Solo le settimane che toccano il mese (4, 5 o 6): righe più alte.
    private var weeks: [[Date]] {
        CalendarMath.monthGrid(for: month, calendar: calendar).filter { week in
            week.contains { CalendarMath.isSameMonth($0, month, calendar: calendar) }
        }
    }

    var body: some View {
        VStack(spacing: showsEventChips ? 0 : DS.s) {
            weekdayHeader
            if showsEventChips {
                richGrid
            } else {
                compactGrid
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            if showsEventChips && showsWeekNumbers {
                Color.clear.frame(width: weekNumberWidth, height: 1)
            }
            ForEach(Array(CalendarMath.orderedWeekdaySymbols(calendar: calendar).enumerated()),
                    id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.dsCaption.weight(.semibold))
                    .foregroundStyle(index >= 5 ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, showsEventChips ? DS.xs : 0)
    }

    // MARK: Compatta (iPhone)

    private var compactGrid: some View {
        ForEach(weeks, id: \.first) { week in
            HStack(spacing: 0) {
                ForEach(week, id: \.self) { day in
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
                        if isToday { Circle().fill(Color.accentColor) }
                    }
                    .background {
                        if isSelected {
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                .padding(isToday ? -3 : 0)
                                .matchedGeometryEffect(id: "month-selection", in: selectionNamespace)
                        }
                    }

                // F25 — i pallini restano anche con la heatmap.
                HStack(spacing: 3) {
                    ForEach(Array(dayTasks.prefix(3).enumerated()), id: \.offset) { _, task in
                        Circle()
                            .fill(CalendarEventBar.tint(for: task))
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
                        .fill(Color.accentColor.opacity(Self.heatOpacity(dayTasks.count)))
                        .padding(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Ricca (Mac/iPad)

    private var richGrid: some View {
        let weeks = weeks
        let rowHeight = rowHeight(weekCount: weeks.count)
        let maxLanes = max(1, Int((rowHeight - dayNumberHeight - 4) / (laneHeight + laneGap)))
        return VStack(spacing: 0) {
            ForEach(Array(weeks.enumerated()), id: \.element.first) { index, week in
                if index > 0 { Divider() }
                weekRow(week, height: rowHeight, maxLanes: maxLanes)
            }
            if fillsHeight { Spacer(minLength: 0) }
        }
        .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            gridHeight = height
        }
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.medium)
                .strokeBorder(DSColor.hairline)
        }
    }

    /// Altezza di una riga: riempie lo spazio (a riposo) o fissa (in scroll).
    private func rowHeight(weekCount: Int) -> CGFloat {
        guard fillsHeight, gridHeight > 0, weekCount > 0 else { return fixedRowHeight }
        let dividers = CGFloat(weekCount - 1)
        return max(minimumRowHeight, (gridHeight - dividers) / CGFloat(weekCount))
    }

    private func weekRow(_ week: [Date], height: CGFloat, maxLanes: Int) -> some View {
        let tasks = CalendarWeekLayout.tasks(in: week, from: tasksByDay, calendar: calendar)
        let layout = CalendarWeekLayout(
            columns: week.count,
            segments: CalendarWeekLayout.segments(for: tasks, days: week, calendar: calendar)
        )
        let visible = layout.visiblePlacements(maxLanes: maxLanes)
        let hidden = layout.hiddenCounts(maxLanes: maxLanes)
        let taskByID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let dayCounts = week.map { (tasksByDay[calendar.startOfDay(for: $0)] ?? []).count }

        return HStack(spacing: 0) {
            if showsWeekNumbers, let first = week.first {
                Text("\(calendar.component(.weekOfYear, from: first))")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: weekNumberWidth, height: height, alignment: .top)
                    .padding(.top, 8)
                    .overlay(alignment: .trailing) { Divider() }
            }
            GeometryReader { geo in
                let columnWidth = geo.size.width / CGFloat(max(week.count, 1))
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.element) { index, day in
                            dayCell(day, count: dayCounts[index])
                                .frame(width: columnWidth, height: height)
                                .overlay(alignment: .leading) {
                                    if index > 0 { Divider() }
                                }
                        }
                    }

                    ForEach(visible) { placement in
                        if let task = taskByID[placement.segment.id] {
                            CalendarEventBar(task: task, segment: placement.segment)
                                .frame(width: max(0, CGFloat(placement.segment.length) * columnWidth - 6),
                                       height: laneHeight)
                                .offset(x: CGFloat(placement.segment.start) * columnWidth + 3,
                                        y: dayNumberHeight + CGFloat(placement.lane) * (laneHeight + laneGap))
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
                        }
                    }

                    ForEach(Array(hidden.enumerated()), id: \.offset) { index, count in
                        if count > 0 {
                            Button {
                                selectedDay = week[index]
                            } label: {
                                Text("+\(count) altr\(count == 1 ? "o" : "i")")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .frame(width: columnWidth - 6, height: laneHeight, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .offset(x: CGFloat(index) * columnWidth + 3,
                                    y: dayNumberHeight + CGFloat(maxLanes - 1) * (laneHeight + laneGap))
                        }
                    }
                }
            }
            .frame(height: height)
        }
    }

    private func dayCell(_ day: Date, count: Int) -> some View {
        MonthDayCell(
            day: day,
            isCurrentMonth: CalendarMath.isSameMonth(day, month, calendar: calendar),
            isToday: calendar.isDateInToday(day),
            isSelected: calendar.isDate(day, inSameDayAs: selectedDay),
            isWeekend: calendar.isDateInWeekend(day),
            heat: showsHeatmap && count > 0 ? Self.heatOpacity(count) : 0,
            selectionNamespace: selectionNamespace,
            onSelect: { selectedDay = day },
            onCreate: { createTask(on: day) },
            onDrop: { reschedule($0, to: day) }
        )
    }

    // MARK: Operatività (drag → ri-data, doppio-tap → crea)

    /// Ri-data l'attività trascinata (ora preservata) e seleziona il giorno.
    private func reschedule(_ idString: String, to day: Date) -> Bool {
        var moved = false
        withAnimation(.dsSoft) {
            moved = CalendarActions.reschedule(taskID: idString, to: day, in: modelContext, calendar: calendar)
            if moved { selectedDay = day }
        }
        return moved
    }

    /// Crea un'attività su `day` e apre subito l'editor. Nel mese non c'è
    /// un'ora: parte alle 9:00 per 1h, modificabile.
    private func createTask(on day: Date) {
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        selectedDay = day
        CalendarActions.createTask(start: start, end: start.addingTimeInterval(3600),
                                   in: modelContext, router: router)
    }

    static func heatOpacity(_ count: Int) -> Double {
        switch count {
        case 0: 0
        case 1: 0.08
        case 2: 0.15
        case 3: 0.24
        default: 0.34
        }
    }

}

// MARK: - Cella del giorno (ricca)

/// Una cella del Mese ricco: numero (oggi pieno, selezione ad anello che
/// scivola), sfondo weekend/heatmap, hover e bersaglio del rilascio. Stato
/// proprio: passarci sopra o trascinarci qualcosa ridisegna solo lei.
private struct MonthDayCell: View {
    let day: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isWeekend: Bool
    /// Opacità della heatmap (0 = spenta).
    let heat: Double
    let selectionNamespace: Namespace.ID
    let onSelect: () -> Void
    let onCreate: () -> Void
    let onDrop: (String) -> Bool

    @State private var isHovered = false
    @State private var isTargeted = false

    private let calendar = Calendar.app

    private var dayLabel: String {
        let number = calendar.component(.day, from: day)
        guard number == 1 else { return "\(number)" }
        return day.appFormatted(.dateTime.day().month(.abbreviated))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            background
            Text(dayLabel)
                .font(.system(size: 12, weight: isToday ? .bold : .medium).monospacedDigit())
                .foregroundStyle(numberColor)
                .padding(.horizontal, dayLabel.count > 2 ? 6 : 0)
                .frame(minWidth: 22, minHeight: 22)
                .background {
                    if isToday { Capsule().fill(Color.accentColor) }
                }
                .background {
                    if isSelected {
                        Capsule()
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                            .padding(isToday ? -3 : 0)
                            .matchedGeometryEffect(id: "month-selection", in: selectionNamespace)
                    }
                }
                .padding(4)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onCreate() }
        .onTapGesture { onSelect() }
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            return onDrop(first)
        } isTargeted: { targeted in
            withAnimation(.dsQuick) { isTargeted = targeted }
        }
        .onHover { hovering in
            withAnimation(.dsQuick) { isHovered = hovering }
        }
        .opacity(isCurrentMonth ? 1 : 0.5)
    }

    private var numberColor: Color {
        if isToday { return .white }
        return isCurrentMonth ? .primary : .secondary
    }

    @ViewBuilder
    private var background: some View {
        ZStack {
            if heat > 0 {
                Color.accentColor.opacity(heat)
            } else if isWeekend {
                Color.primary.opacity(0.025)
            }
            if isHovered {
                Color.primary.opacity(0.035)
            }
            if isTargeted {
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .fill(Color.accentColor.opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.small)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                    .padding(2)
            }
        }
    }
}
