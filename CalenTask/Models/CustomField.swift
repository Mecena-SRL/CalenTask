import Foundation
import SwiftData

// Maps to future Supabase table `custom_field_definitions`.
// Workspace-wide when projectID is nil, otherwise scoped to one project (D12).
@Model
final class CustomFieldDefinition {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var projectID: UUID?
    var name: String = ""
    var typeRaw: String = ""
    /// Options for .select fields; empty otherwise.
    var options: [String] = []
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var type: CustomFieldType {
        get { CustomFieldType(rawValue: typeRaw) ?? .text }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        projectID: UUID? = nil,
        name: String,
        type: CustomFieldType,
        options: [String] = [],
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.projectID = projectID
        self.name = name
        self.typeRaw = type.rawValue
        self.options = options
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

// Maps to future Supabase table `custom_field_values`.
// ID-based edge (like TaskDependency): one value per (field, task) pair.
// The raw string encodes per type: text/url as-is, number via `Double`,
// date as ISO 8601, checkbox as "true"/"false", select as the chosen option.
@Model
final class CustomFieldValue {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var fieldID: UUID = UUID()
    var taskID: UUID = UUID()
    var valueRaw: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var dateValue: Date? {
        get { ISO8601DateFormatter().date(from: valueRaw) }
        set { valueRaw = newValue.map { ISO8601DateFormatter().string(from: $0) } ?? "" }
    }

    var numberValue: Double? {
        get { Double(valueRaw) }
        set { valueRaw = newValue.map { String($0) } ?? "" }
    }

    var boolValue: Bool {
        get { valueRaw == "true" }
        set { valueRaw = newValue ? "true" : "false" }
    }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        fieldID: UUID,
        taskID: UUID,
        valueRaw: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.fieldID = fieldID
        self.taskID = taskID
        self.valueRaw = valueRaw
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
