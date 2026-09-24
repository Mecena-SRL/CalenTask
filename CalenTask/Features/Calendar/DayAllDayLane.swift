import SwiftUI

/// La fascia "Tutto il giorno" del Giorno-hub: le scadenze/attività del giorno
/// senza orario, **fissa** sopra la griglia/Gantt che scorre. Ogni chip è
/// spuntabile (la completi qui) o trascinabile su un orario della griglia.
struct AllDayLaneView: View {
    let tasks: [TodoTask]

    var body: some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: DS.xs) {
                Text("Tutto il giorno")
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.s) {
                        ForEach(tasks, id: \.id) { task in
                            chip(task)
                        }
                    }
                }
            }
        }
    }

    private func chip(_ task: TodoTask) -> some View {
        let tint = task.project.map { Color(hex: $0.colorHex) } ?? Color.accentColor
        return HStack(spacing: DS.xs) {
            DSCheckToggle(isDone: task.isDone, font: .callout) {
                withAnimation(.dsSoft) { task.toggleDone() }
            }
            TaskOpenLink(task: task) {
                Text(task.title)
                    .font(.dsCaption.weight(.medium))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DS.s)
        .padding(.vertical, DS.xs)
        .background(tint.opacity(task.isDone ? 0.06 : 0.12), in: Capsule())
        .draggable(task.id.uuidString)
        .taskContextMenu(task)
    }
}
