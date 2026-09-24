import Foundation
import SwiftData

// Maps to future Supabase table `saved_views`.
// A persisted view configuration: view type + serialized filters (D16).
// Workspace-wide when projectID is nil.
@Model
final class SavedView {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var projectID: UUID?
    var name: String = ""
    var viewTypeRaw: String = ""
    /// JSON-encoded `SavedViewFilters`; kept as a string for forward compatibility.
    var filtersJSON: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var viewType: ProjectViewType {
        get { ProjectViewType(rawValue: viewTypeRaw) ?? .list }
        set { viewTypeRaw = newValue.rawValue }
    }

    var filters: SavedViewFilters {
        get {
            guard let data = filtersJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(SavedViewFilters.self, from: data)
            else { return SavedViewFilters() }
            return decoded
        }
        set {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            filtersJSON = (try? encoder.encode(newValue))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }
    }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        projectID: UUID? = nil,
        name: String,
        viewType: ProjectViewType,
        filters: SavedViewFilters = SavedViewFilters(),
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.projectID = projectID
        self.name = name
        self.viewTypeRaw = viewType.rawValue
        self.filtersJSON = "{}"
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.filters = filters
    }
}

/// Combinable filters for saved views. All criteria are AND-ed; empty arrays
/// mean "no constraint". Extend freely: unknown keys decode away gracefully.
nonisolated struct SavedViewFilters: Codable, Equatable {
    var statuses: [TaskStatus] = []
    var priorities: [TaskPriority] = []
    var kinds: [TaskKind] = []
    var tagIDs: [UUID] = []
    var dueWithinDays: Int?
    var includeDone: Bool = false

    init() {}
}
