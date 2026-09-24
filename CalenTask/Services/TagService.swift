import Foundation
import SwiftData

/// Keeps `TodoTask.tags` in sync with the #hashtags typed in title/notes
/// (D21). Tags are workspace-scoped; new names get a rotating default color
/// the user can change in the tag manager.
@MainActor
enum TagService {
    /// Default palette assigned round-robin to brand-new tags.
    static let defaultPalette = [
        "#2563EB", "#DC2626", "#D97706", "#059669",
        "#7C3AED", "#DB2777", "#0E7490", "#64748B",
    ]

    /// Re-derives the task's tags from its text. Existing Tag entities are
    /// reused (matched by name within the workspace); missing ones are created.
    static func syncTags(for task: TodoTask, in context: ModelContext) {
        let names = task.parsedTagNames
        let workspaceID = task.workspaceID

        do {
            let descriptor = FetchDescriptor<Tag>(
                predicate: #Predicate { $0.workspaceID == workspaceID && $0.deletedAt == nil }
            )
            let existing = try context.fetch(descriptor)
            var byName = Dictionary(grouping: existing, by: \.name).compactMapValues(\.first)

            var resolved: [Tag] = []
            for name in names {
                if let tag = byName[name] {
                    resolved.append(tag)
                } else {
                    let color = defaultPalette[abs(name.hashValue) % defaultPalette.count]
                    let tag = Tag(workspaceID: workspaceID, name: name, colorHex: color)
                    context.insert(tag)
                    byName[name] = tag
                    resolved.append(tag)
                }
            }
            // Full replace: the text is the source of truth for labels.
            if Set(task.tags.map(\.id)) != Set(resolved.map(\.id)) {
                task.tags = resolved
            }
        } catch {
            reportFailure("Tag sync failed: \(error)")
        }
    }
}
