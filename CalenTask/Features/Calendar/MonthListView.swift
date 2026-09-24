import Foundation
import SwiftUI

/// Il Mese "a elenco": i giorni del mese con qualcosa in programma, uno
/// sotto l'altro come un'agenda, con l'intestazione del giorno che resta in
/// alto mentre scorri. Si apre sul giorno scelto (o sul primo da oggi).
struct MonthListView: View {
    let month: Date
    @Binding var selectedDay: Date
    let tasksByDay: [Date: [TodoTask]]

    private let calendar = Calendar.app

    /// I giorni del mese che hanno almeno un elemento.
    private var days: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        var result: [Date] = []
        var day = interval.start
        while day < interval.end {
            if !items(on: day).isEmpty { result.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    private func items(on day: Date) -> [TodoTask] {
        (tasksByDay[calendar.startOfDay(for: day)] ?? [])
            .filter { !$0.isPhase }
            .sorted { a, b in
                let timeA = time(of: a, on: day), timeB = time(of: b, on: day)
                switch (timeA, timeB) {
                case (nil, nil): return a.title.localizedStandardCompare(b.title) == .orderedAscending
                case (nil, _): return true
                case (_, nil): return false
                case let (lhs?, rhs?): return lhs < rhs
                }
            }
    }

    private func time(of task: TodoTask, on day: Date) -> Date? {
        guard !task.allDay, let startAt = task.startAt,
              calendar.isDate(startAt, inSameDayAs: day) else { return nil }
        return startAt
    }

    var body: some View {
        let days = days
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.l, pinnedViews: [.sectionHeaders]) {
                    if days.isEmpty {
                        ContentUnavailableView(
                            "Mese libero",
                            systemImage: "calendar",
                            description: Text("Nessun evento, attività o scadenza in \(month.appFormatted(.dateTime.month(.wide))).")
                        )
                        .padding(.top, DS.xxl)
                    }
                    ForEach(days, id: \.self) { day in
                        Section {
                            VStack(spacing: 0) {
                                let dayItems = items(on: day)
                                ForEach(Array(dayItems.enumerated()), id: \.element.id) { index, task in
                                    MonthListRow(task: task, time: time(of: task, on: day), day: day)
                                    if index < dayItems.count - 1 {
                                        Divider().padding(.leading, 70)
                                    }
                                }
                            }
                            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
                            .overlay {
                                RoundedRectangle(cornerRadius: DS.Radius.medium)
                                    .strokeBorder(calendar.isDate(day, inSameDayAs: selectedDay)
                                                  ? Color.accentColor.opacity(0.6) : DSColor.hairline)
                            }
                        } header: {
                            dayHeader(day)
                        }
                        .id(day)
                    }
                }
                .padding(DS.l)
            }
            .onAppear {
                if let target = scrollTarget(in: days) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    /// Il giorno scelto se ha elementi, altrimenti il primo da oggi in poi.
    private func scrollTarget(in days: [Date]) -> Date? {
        if let selected = days.first(where: { calendar.isDate($0, inSameDayAs: selectedDay) }) {
            return selected
        }
        let today = calendar.startOfDay(for: .now)
        return days.first { $0 >= today }
    }

    private func dayHeader(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        return Button {
            withAnimation(.dsQuick) { selectedDay = calendar.startOfDay(for: day) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.s) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                Text(day.appFormatted(.dateTime.weekday(.wide)).capitalized)
                    .font(.dsMeta.weight(.medium))
                    .foregroundStyle(isToday ? Color.accentColor : .secondary)
                if isToday {
                    Text("Oggi")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
                Spacer()
                Text("\(items(on: day).count)")
                    .font(.dsCaption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, DS.xs)
            .padding(.horizontal, DS.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Una riga dell'elenco: ora (o "giorno"/scadenza), barra colorata,
/// titolo e contesto. Apre l'attività; si trascina su un giorno della
/// griglia come le altre.
private struct MonthListRow: View {
    @Bindable var task: TodoTask
    let time: Date?
    let day: Date

    @State private var isHovered = false

    private var tint: Color { CalendarEventBar.tint(for: task) }
    private var isCheckable: Bool { task.kind == .task || task.kind == .reminder }

    private var timeLabel: String {
        if let time { return time.dsTimeLabel }
        if let dueAt = task.dueAt, Calendar.app.isDate(dueAt, inSameDayAs: day) { return "Scad." }
        return "Giorno"
    }

    private var subtitle: String? {
        let parts = [task.project?.name, task.locationName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: DS.m) {
            Text(timeLabel)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(time == nil ? .tertiary : .secondary)
                .frame(width: 44, alignment: .trailing)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint.opacity(task.isDone ? 0.35 : 1))
                .frame(width: 3, height: 28)
            TaskOpenLink(task: task) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.dsMeta.weight(.medium))
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.dsCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            if isCheckable {
                DSCheckToggle(isDone: task.isDone, font: .body) {
                    withAnimation(.dsSoft) { task.toggleDone() }
                }
            }
        }
        .padding(.horizontal, DS.m)
        .padding(.vertical, DS.s)
        .background(isHovered ? Color.primary.opacity(0.03) : .clear)
        .onHover { isHovered = $0 }
        .draggable(task.id.uuidString)
        .taskContextMenu(task)
    }
}
