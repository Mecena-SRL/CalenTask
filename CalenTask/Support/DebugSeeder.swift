#if DEBUG
import Foundation
import SwiftData

/// Generates bulk sample data for performance sanity checks (macOS Debug menu).
@MainActor
enum DebugSeeder {
    static func generate(count: Int = 500, in context: ModelContext) throws {
        let (workspace, me) = try SeedService.ensureSeed(in: context)

        let project = try TemplateService.apply(
            TemplateCatalog.feature,
            projectName: "Stress test \(Int.random(in: 100...999))",
            workspaceID: workspace.id,
            createdBy: me.id,
            in: context
        )
        let phases = project.phaseTasks
        let calendar = Calendar.current

        for index in 0..<count {
            let task = TodoTask(
                workspaceID: workspace.id,
                title: "Attività di prova \(index + 1)",
                status: TaskStatus.allCases.randomElement() ?? .todo,
                priority: TaskPriority.allCases.randomElement() ?? .normal,
                createdByID: me.id
            )
            if index.isMultiple(of: 3) {
                task.dueAt = calendar.date(byAdding: .day, value: Int.random(in: -10...30), to: .now.startOfDay)
            }
            if index.isMultiple(of: 5) {
                task.startAt = calendar.date(byAdding: .hour, value: Int.random(in: -72...240), to: .now)
            }
            task.sortOrder = index
            context.insert(task)
            // Two thirds spread across phases, one third stays in the Inbox.
            if !index.isMultiple(of: 3), let phase = phases.randomElement() {
                task.project = project
                task.parentTask = phase
            }
        }
        try context.save()
    }
}
#endif
