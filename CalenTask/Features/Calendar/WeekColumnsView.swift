import Foundation
import SwiftUI
import SwiftData

/// La Settimana "a colonne" (planner): per ogni giorno la pila delle sue
/// attività ed eventi, senza ore — per chi pianifica per compiti più che per
/// orari. Prima quello che dura tutto il giorno e le scadenze, poi gli
/// impegni con orario in ordine.
/// - **Trascina** una scheda su un'altra colonna per spostarla (ora
///   preservata); **doppio clic** su una colonna crea lì.
/// - Tocca l'intestazione per aprire il giorno.
struct WeekColumnsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    let weekStart: Date
    var dayCount = 7
    let data: CalendarTaskIndex
    /// Ora a cui nasce un'attività creata con il doppio clic.
    var workStartHour = 9
    var transitionEdge: Edge = .trailing
    var onOpenDay: (Date) -> Void = { _ in }

    private let calendar = Calendar.app

    private var days: [Date] {
        (0..<max(dayCount, 1)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: DS.s) {
                ForEach(days, id: \.self) { day in
                    WeekPlannerColumn(
                        day: day,
                        items: items(on: day),
                        onOpenDay: { onOpenDay(day) },
                        onCreate: { create(on: day) },
                        onDrop: { reschedule($0, to: day) }
                    )
                }
            }
            .id(calendar.startOfDay(for: weekStart))
            .transition(.push(from: transitionEdge))
        }
        .clipped()
    }

    /// Prima ciò che non ha un orario quel giorno, poi gli orari in ordine.
    private func items(on day: Date) -> [TodoTask] {
        data.tasks(on: day)
            .filter { !$0.isPhase }
            .sorted { a, b in
                let timeA = WeekPlannerCard.time(of: a, on: day, calendar: calendar)
                let timeB = WeekPlannerCard.time(of: b, on: day, calendar: calendar)
                switch (timeA, timeB) {
                case (nil, nil): return a.title.localizedStandardCompare(b.title) == .orderedAscending
                case (nil, _): return true
                case (_, nil): return false
                case let (lhs?, rhs?): return lhs < rhs
                }
            }
    }

    private func create(on day: Date) {
        let start = calendar.date(bySettingHour: workStartHour, minute: 0, second: 0, of: day) ?? day
        CalendarActions.createTask(start: start, end: start.addingTimeInterval(3600),
                                   in: modelContext, router: router)
    }

    private func reschedule(_ idString: String, to day: Date) -> Bool {
        var moved = false
        withAnimation(.dsSoft) {
            moved = CalendarActions.reschedule(taskID: idString, to: day, in: modelContext, calendar: calendar)
        }
        return moved
    }
}

// MARK: - Colonna

/// Una colonna del planner: intestazione (oggi evidenziato), schede che
/// scorrono, bersaglio del rilascio con stato proprio.
private struct WeekPlannerColumn: View {
    let day: Date
    let items: [TodoTask]
    let onOpenDay: () -> Void
    let onCreate: () -> Void
    let onDrop: (String) -> Bool

    @State private var isTargeted = false

    private let calendar = Calendar.app
    private var isToday: Bool { calendar.isDateInToday(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            header
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(items, id: \.id) { task in
                        WeekPlannerCard(task: task, day: day)
                    }
                    if items.isEmpty {
                        Text("Libero")
                            .font(.dsCaption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.l)
                    }
                }
                .padding(.bottom, DS.l)
                .animation(.dsSoft, value: items.map(\.id))
            }
            .scrollIndicators(.never)
        }
        .padding(DS.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            isToday ? Color.accentColor.opacity(0.06) : DSColor.surface,
            in: RoundedRectangle(cornerRadius: DS.Radius.medium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.medium)
                .strokeBorder(isTargeted ? Color.accentColor : DSColor.hairline,
                              lineWidth: isTargeted ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onCreate() }
        .dropDestination(for: String.self) { dropped, _ in
            guard let first = dropped.first else { return false }
            return onDrop(first)
        } isTargeted: { targeted in
            withAnimation(.dsQuick) { isTargeted = targeted }
        }
    }

    private var header: some View {
        Button(action: onOpenDay) {
            HStack(spacing: DS.xs) {
                Text(day.appFormatted(.dateTime.weekday(.abbreviated)))
                    .font(.dsCaption)
                    .foregroundStyle(isToday ? .white : .secondary)
                Text("\(calendar.component(.day, from: day))")
                    .font(.dsNumeric.weight(.semibold))
                    .foregroundStyle(isToday ? .white : .primary)
                Spacer(minLength: 0)
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isToday ? .white.opacity(0.85) : .secondary)
                }
            }
            .padding(.horizontal, DS.s)
            .padding(.vertical, 4)
            .background {
                if isToday { Capsule().fill(Color.accentColor) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Apri \(day.appFormatted(.dateTime.weekday(.wide).day().month()))")
    }
}

// MARK: - Scheda

/// Una scheda del planner: spunta (per le attività), orario o "tutto il
/// giorno"/scadenza, titolo e progetto. Si trascina su un altro giorno.
private struct WeekPlannerCard: View {
    @Bindable var task: TodoTask
    let day: Date

    @State private var isHovered = false

    private let calendar = Calendar.app
    private var tint: Color { CalendarEventBar.tint(for: task) }
    private var isCheckable: Bool { task.kind == .task || task.kind == .reminder }

    /// L'orario dell'elemento in quel giorno, se ne ha uno.
    static func time(of task: TodoTask, on day: Date, calendar: Calendar) -> Date? {
        guard !task.allDay, let startAt = task.startAt,
              calendar.isDate(startAt, inSameDayAs: day) else { return nil }
        return startAt
    }

    private var caption: String {
        if let time = Self.time(of: task, on: day, calendar: calendar) {
            let end = task.endAt ?? time.addingTimeInterval(3600)
            return calendar.isDate(end, inSameDayAs: day) ? "\(time.dsTimeLabel) – \(end.dsTimeLabel)" : time.dsTimeLabel
        }
        if let dueAt = task.dueAt, calendar.isDate(dueAt, inSameDayAs: day) {
            return "Scadenza"
        }
        return "Tutto il giorno"
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.s) {
            if isCheckable {
                DSCheckToggle(isDone: task.isDone, font: .callout) {
                    withAnimation(.dsSoft) { task.toggleDone() }
                }
            }
            TaskOpenLink(task: task) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .opacity(0.85)
                    Text(task.title)
                        .font(.dsCaption.weight(.semibold))
                        .strikethrough(task.isDone)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if let project = task.project {
                        Text(project.name)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .padding(DS.s)
        .padding(.leading, DS.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsEventBlock(tint: tint, isDone: task.isDone)
        .scaleEffect(isHovered ? 1.02 : 1)
        .shadow(color: .black.opacity(isHovered ? 0.12 : 0), radius: 4, y: 2)
        .onHover { hovering in
            withAnimation(.dsQuick) { isHovered = hovering }
        }
        .draggable(task.id.uuidString)
        .taskContextMenu(task)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}
