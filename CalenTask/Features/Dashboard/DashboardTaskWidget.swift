import SwiftUI

/// Una lista breve sulla Home, espandibile senza perdere il contesto.
struct DashboardTaskWidget: View {
    let title: String
    let tasks: [TodoTask]
    var tint: Color = .primary
    var previewCount: Int = 6

    @State private var isExpanded = false

    private var displayedTasks: [TodoTask] {
        isExpanded ? tasks : Array(tasks.prefix(previewCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: title, count: tasks.count, tint: tint)
            VStack(spacing: 0) {
                ForEach(displayedTasks, id: \.id) { task in
                    TaskOpenLink(task: task) {
                        TaskRow(task: task) {
                            withAnimation(.dsSoft) { task.toggleDone() }
                        }
                    }
                    .taskContextMenu(task)
                    .padding(.horizontal, DS.m)
                    if task.id != displayedTasks.last?.id {
                        Divider().padding(.leading, DS.xxl + DS.s)
                    }
                }
                if tasks.count > previewCount {
                    Divider().padding(.horizontal, DS.m)
                    Button {
                        withAnimation(.dsSoft) { isExpanded.toggle() }
                    } label: {
                        HStack {
                            Text(isExpanded ? "Mostra meno" : "Mostra tutte (\(tasks.count))")
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.dsCaption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(minHeight: DS.xxl + DS.m)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DS.m)
                    .accessibilityLabel(isExpanded ? "Comprimi \(title)" : "Mostra tutte le attività: \(title)")
                }
            }
            .padding(.vertical, DS.s)
            .background(DSColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
    }
}
