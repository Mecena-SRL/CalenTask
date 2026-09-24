import SwiftUI
import SwiftData

/// Standard task row: completion toggle + title + metadata line.
/// Swipe actions / context menus belong to the hosting list.
struct TaskRow: View {
    let task: TodoTask
    var showProject: Bool = true
    var onToggleDone: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.m) {
            DSCheckToggle(isDone: task.isDone, onCommit: onToggleDone)

            VStack(alignment: .leading, spacing: DS.xs) {
                HStack(spacing: DS.s) {
                    PriorityDot(priority: task.priority)
                    Text(task.title)
                        .font(.dsRowTitle)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .lineLimit(2)
                }
                if hasMetadata {
                    HStack(spacing: DS.s) {
                        if showProject, let project = task.project {
                            Label(project.name, systemImage: "folder")
                                .foregroundStyle(Color(hex: project.colorHex))
                        }
                        if let dueAt = task.dueAt {
                            Label(dueAt.dsRelativeLabel, systemImage: "flag")
                                .foregroundStyle(task.isOverdue ? DSColor.overdue : .secondary)
                        }
                        // D52 — meteo sulle attività dei prossimi giorni.
                        if let weatherDay = task.startAt ?? task.dueAt,
                           weatherDay >= Date.now.startOfDay,
                           let forecast = WeatherService.shared.forecast(for: weatherDay) {
                            HStack(spacing: 2) {
                                Image(systemName: forecast.symbolName)
                                    .symbolRenderingMode(.multicolor)
                                Text(forecast.tMaxLabel)
                                    .font(.dsNumeric)
                            }
                            .foregroundStyle(.secondary)
                        }
                        if let startAt = task.startAt {
                            Label(startAt.dsTimeLabel, systemImage: "clock")
                                .foregroundStyle(.secondary)
                        }
                        if task.remindAt != nil {
                            Image(systemName: "bell")
                                .foregroundStyle(.secondary)
                        }
                        if !task.subtasks.isEmpty {
                            let done = task.subtasks.filter(\.isDone).count
                            Text("\(done)/\(task.subtasks.count)")
                                .font(.dsNumeric)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(task.orderedTags.prefix(2), id: \.id) { tag in
                            TagChip(tag: tag)
                        }
                    }
                    .font(.dsCaption)
                    .labelStyle(.titleAndIcon)
                }
            }
            Spacer(minLength: 0)
            if task.status == .doing || task.status == .blocked {
                StatusBadge(status: task.status)
            }
        }
        .padding(.vertical, DS.xs)
        .contentShape(Rectangle())
    }

    private var hasMetadata: Bool {
        (showProject && task.project != nil) || task.dueAt != nil || task.startAt != nil
            || task.remindAt != nil || !task.subtasks.isEmpty || !task.orderedTags.isEmpty
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return List {
        ForEach(preview.tasks.prefix(5), id: \.id) { task in
            TaskRow(task: task) {}
        }
    }
    .modelContainer(preview.container)
}
