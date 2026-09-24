import SwiftUI

/// Owns transient hover/tap state at the event layer. Moving the pointer no
/// longer invalidates the calendar's date index, hour grid or other days.
struct CalendarCascadeLayer: View {
    let clusters: [[TodoTask]]
    let people: [UserProfile]
    let hourHeight: CGFloat
    let laneWidth: CGFloat
    var leadingInset: CGFloat = 0
    var minimumMinutes: Int = 30

    @State private var frontTaskID: UUID?
    @State private var hoveredTaskID: UUID?
    /// Il blocco che si sta spostando/allungando: sopra a tutto, anche agli
    /// altri cluster che attraversa.
    @State private var draggingTaskID: UUID?
    private let calendar = Calendar.app

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
                let activeID = CalendarMath.activeCascadeID(
                    in: cluster, hovered: hoveredTaskID, tapped: frontTaskID
                )
                let raisedID = activeID ?? cluster.last?.id
                ForEach(Array(cluster.enumerated()), id: \.element.id) { depth, task in
                    let stacked = cluster.count > 1
                    let inset = stacked ? CalendarMath.cascadeInset(depth: depth, laneWidth: laneWidth) : 0
                    let isFront = !stacked || task.id == raisedID
                    TimeBlockView(
                        task: task,
                        people: people,
                        hourHeight: hourHeight,
                        snapMinutes: 15,
                        yPosition: yPosition(for: task),
                        height: blockHeight(for: task),
                        xOffset: leadingInset + inset,
                        width: max(20, laneWidth - inset),
                        cascaded: stacked,
                        isFront: isFront,
                        isLifted: stacked && task.id == activeID,
                        onRaise: { frontTaskID = task.id },
                        onHover: { hovering in
                            if hovering {
                                hoveredTaskID = task.id
                            } else if hoveredTaskID == task.id {
                                hoveredTaskID = nil
                            }
                        },
                        onDragStateChange: { dragging in
                            if dragging {
                                draggingTaskID = task.id
                            } else if draggingTaskID == task.id {
                                draggingTaskID = nil
                            }
                        }
                    )
                    .zIndex(task.id == draggingTaskID ? 5000 : (isFront ? 1000 : Double(depth)))
                }
            }
        }
    }

    private func yPosition(for task: TodoTask) -> CGFloat {
        guard let start = task.startAt else { return 0 }
        let time = calendar.dateComponents([.hour, .minute], from: start)
        return CGFloat((time.hour ?? 0) * 60 + (time.minute ?? 0)) / 60 * hourHeight
    }

    private func blockHeight(for task: TodoTask) -> CGFloat {
        guard let start = task.startAt else { return hourHeight }
        let end = task.endAt ?? start.addingTimeInterval(3600)
        return CGFloat(max(minimumMinutes, Int(end.timeIntervalSince(start) / 60))) / 60 * hourHeight
    }
}
