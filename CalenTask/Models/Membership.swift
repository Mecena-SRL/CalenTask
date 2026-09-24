import Foundation
import SwiftData

// Maps to future Supabase table `memberships` (user ↔ workspace, with role).
@Model
final class Membership {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var userID: UUID = UUID()
    var roleRaw: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var role: MembershipRole {
        get { MembershipRole(rawValue: roleRaw) ?? .member }
        set { roleRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), workspaceID: UUID, userID: UUID, role: MembershipRole, createdAt: Date = .now) {
        self.id = id
        self.workspaceID = workspaceID
        self.userID = userID
        self.roleRaw = role.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
