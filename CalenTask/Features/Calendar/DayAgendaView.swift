import SwiftUI

/// Agenda for the selected day: timed tasks chronologically, then all-day
/// deadlines. L'header (data, meteo, "Aggiungi") vive nel `DayHeaderView`
/// condiviso con la Griglia.
struct DayAgendaView: View {
    let day: Date
    let tasks: [TodoTask]

    private let calendar = Calendar.app

    private var timed: [TodoTask] {
        tasks
            .filter { task in
                guard !task.allDay, let startAt = task.startAt else { return false }
                return calendar.isDate(startAt, inSameDayAs: day)
            }
            .sorted { ($0.startAt ?? .distantPast) < ($1.startAt ?? .distantPast) }
    }

    private var allDay: [TodoTask] {
        tasks.filter { task in
            if task.allDay {
                return (task.startAt ?? task.dueAt).map {
                    calendar.isDate($0, inSameDayAs: day)
                } ?? false
            }
            guard let dueAt = task.dueAt else { return false }
            let sameDay = calendar.isDate(dueAt, inSameDayAs: day)
            let alreadyTimed = task.startAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false
            return sameDay && !alreadyTimed
        }
    }

    var body: some View {
        // Resolve these once: the old row loop sorted the day's tasks again
        // for every separator and count check.
        let timed = timed
        let allDay = allDay
        VStack(alignment: .leading, spacing: DS.s) {
            if timed.isEmpty && allDay.isEmpty {
                Text("Niente in programma.")
                    .font(.dsMeta)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DS.xl)
            } else {
                // F22 — agenda alla Apple Calendar: colonna orari, barra
                // colorata, titolo + contesto. La linea "adesso" separa
                // passato e futuro quando il giorno è oggi.
                VStack(spacing: 0) {
                    ForEach(Array(timed.enumerated()), id: \.element.id) { index, task in
                        if shouldShowNowLine(before: index, in: timed) {
                            nowSeparator
                        }
                        agendaRow(task, timed: true)
                        if index < timed.count - 1 {
                            Divider().padding(.leading, 76)
                        }
                    }
                    if isToday && !timed.isEmpty && timed.allSatisfy(isPast) {
                        nowSeparator
                    }
                    if !timed.isEmpty && !allDay.isEmpty {
                        sectionLabel("Scadenze del giorno")
                    }
                    ForEach(Array(allDay.enumerated()), id: \.element.id) { index, task in
                        agendaRow(task, timed: false)
                        if index < allDay.count - 1 {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
                .padding(.vertical, DS.s)
                .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.medium)
                        .strokeBorder(DSColor.hairline)
                }
            }
        }
    }

    private var isToday: Bool { calendar.isDateInToday(day) }

    private func isPast(_ task: TodoTask) -> Bool {
        guard let startAt = task.startAt else { return false }
        return (task.endAt ?? startAt.addingTimeInterval(3600)) < .now
    }

    /// La linea "adesso" entra prima del primo evento ancora da venire.
    private func shouldShowNowLine(before index: Int, in timed: [TodoTask]) -> Bool {
        guard isToday else { return false }
        let task = timed[index]
        guard !isPast(task) else { return false }
        return index == 0 || isPast(timed[index - 1])
    }

    private var nowSeparator: some View {
        HStack(spacing: DS.s) {
            Text(Date.now.dsTimeLabel)
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(DSColor.overdue)
            Rectangle()
                .fill(DSColor.overdue)
                .frame(height: 1)
            Circle()
                .fill(DSColor.overdue)
                .frame(width: 5, height: 5)
        }
        .padding(.horizontal, DS.m)
        .padding(.vertical, 2)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.dsCaption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.m)
            .padding(.top, DS.m)
            .padding(.bottom, DS.xs)
    }

    private func agendaRow(_ task: TodoTask, timed: Bool) -> some View {
        HStack(spacing: DS.m) {
            // Colonna orari: inizio sopra, fine sotto (o "giorno" per all-day).
            VStack(alignment: .trailing, spacing: 1) {
                if timed, let startAt = task.startAt {
                    Text(startAt.dsTimeLabel)
                        .font(.dsNumeric.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text((task.endAt ?? startAt.addingTimeInterval(3600)).dsTimeLabel)
                        .font(.dsNumeric)
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "flag")
                        .font(.dsCaption)
                        .foregroundStyle(task.isOverdue ? DSColor.overdue : .secondary)
                }
            }
            .frame(width: 44, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(tint(for: task))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            DSCheckToggle(isDone: task.isDone) {
                withAnimation(.dsSoft) { task.toggleDone() }
            }

            TaskOpenLink(task: task) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.dsMeta.weight(.medium))
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .lineLimit(2)
                    if let context = contextLine(for: task) {
                        Text(context)
                            .font(.dsCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }

            // S5 — Partecipa a un tap; in evidenza nei 10' prima dell'inizio.
            if let url = task.videoCallURL {
                if isImminent(task) {
                    Link(destination: url) {
                        Label("Partecipa", systemImage: "video.fill")
                            .font(.dsCaption.weight(.bold))
                    }
                    .buttonStyle(.dsProminent)
                    .controlSize(.small)
                } else {
                    Link(destination: url) {
                        Image(systemName: "video")
                            .foregroundStyle(Color.accentColor)
                    }
                    .help("Partecipa alla videochiamata")
                }
            }
        }
        .padding(.horizontal, DS.m)
        .padding(.vertical, DS.s)
        .fixedSize(horizontal: false, vertical: true)
        .taskContextMenu(task)
    }

    private func tint(for task: TodoTask) -> Color {
        task.accentTagColorHex.map { Color(hex: $0) }
            ?? task.project.map { Color(hex: $0.colorHex) }
            ?? .accentColor
    }

    private func contextLine(for task: TodoTask) -> String? {
        var pieces: [String] = []
        if let project = task.project { pieces.append(project.name) }
        if let location = task.locationName, !location.isEmpty { pieces.append(location) }
        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }

    /// Mancano meno di 10 minuti all'inizio (o è già in corso).
    private func isImminent(_ task: TodoTask) -> Bool {
        guard let startAt = task.startAt else { return false }
        let lead = startAt.addingTimeInterval(-10 * 60)
        let end = task.endAt ?? startAt.addingTimeInterval(3600)
        return (lead...end).contains(.now)
    }
}
