import SwiftUI
import SwiftData

/// Card used by Board and Kanban columns: quiet, readable, draggable.
struct TaskCardView: View {
    let task: TodoTask
    /// Kanban columns already encode the status — hide the badge there.
    var showsStatus = true
    var onToggleDone: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            HStack(alignment: .firstTextBaseline, spacing: DS.s) {
                if let onToggleDone {
                    DSCheckToggle(isDone: task.isDone, font: .body, onCommit: onToggleDone)
                }
                Text(task.title)
                    .font(.dsMeta.weight(.medium))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                PriorityDot(priority: task.priority)
            }

            if hasMetadata {
                HStack(spacing: DS.s) {
                    if let dueAt = task.dueAt {
                        Label(dueAt.dsRelativeLabel, systemImage: "flag")
                            .foregroundStyle(task.isOverdue ? DSColor.overdue : .secondary)
                    }
                    if let startAt = task.startAt, task.kind == .event {
                        Label(startAt.dsRelativeLabel, systemImage: "calendar")
                            .foregroundStyle(.secondary)
                    }
                    if !task.liveSubtasks.isEmpty {
                        let done = task.liveSubtasks.filter(\.isDone).count
                        Label("\(done)/\(task.liveSubtasks.count)", systemImage: "checklist")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if showsStatus, task.status == .doing || task.status == .blocked {
                        StatusBadge(status: task.status)
                    }
                }
                .font(.dsCaption)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(DS.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .fill(DSElevation.card.surface)
                if let accent = task.accentTagColorHex {
                    // First #label colors the card (D21).
                    RoundedRectangle(cornerRadius: DS.Radius.small)
                        .fill(Color(hex: accent).opacity(0.08))
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.small)
                .strokeBorder(DSColor.hairline)
        }
        .shadow(color: DSColor.ambientShadow, radius: 6, y: 2)
        .contentShape(Rectangle())
    }

    private var hasMetadata: Bool {
        task.dueAt != nil || (task.startAt != nil && task.kind == .event)
            || !task.liveSubtasks.isEmpty
            || (showsStatus && (task.status == .doing || task.status == .blocked))
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return VStack(spacing: DS.m) {
        ForEach(preview.tasks.prefix(3), id: \.id) { task in
            TaskCardView(task: task) {}
        }
    }
    .padding()
    .frame(width: 300)
    .background(DSColor.surfaceSecondary)
    .modelContainer(preview.container)
}
