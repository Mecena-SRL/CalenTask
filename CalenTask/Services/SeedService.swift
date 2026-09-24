import Foundation
import SwiftData

@MainActor
enum SeedService {
    static let workspaceDefaultsKey = "currentWorkspaceID"
    static let userDefaultsKey = "currentUserID"

    static let personalName = "Personale"

    /// Idempotent first-launch seed: SOLO lo spazio personale e l'utente
    /// locale — si parte da zero (D49). Gli altri spazi (la società, il team)
    /// li crea l'utente con `createWorkspace`. Safe a ogni avvio.
    @discardableResult
    static func ensureSeed(in context: ModelContext) throws -> (workspace: Workspace, me: UserProfile) {
        let workspaces = try context.fetch(
            FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.createdAt)])
        )

        let personal: Workspace
        if let existing = workspaces.first(where: { $0.isPersonal && $0.deletedAt == nil }) {
            personal = existing
        } else {
            personal = Workspace(name: personalName, isPersonal: true, colorHex: "#6E56CF")
            context.insert(personal)
        }

        let me = try currentUser(in: context)
        try ensureMemberships(for: me, in: context)
        try dedupeAfterCloudMerge(in: context)
        try context.save()

        let current = try currentWorkspace(in: context) ?? personal
        persistDefaults(workspace: current, user: me)
        return (current, me)
    }

    /// Crea uno spazio di lavoro (la società, un team, un cliente) con la
    /// membership owner dell'utente corrente. Ritorna lo spazio creato.
    @discardableResult
    static func createWorkspace(
        name: String, colorHex: String, in context: ModelContext
    ) throws -> Workspace {
        let workspace = Workspace(name: name, colorHex: colorHex)
        context.insert(workspace)
        let me = try currentUser(in: context)
        context.insert(Membership(workspaceID: workspace.id, userID: me.id, role: .owner))
        try context.save()
        return workspace
    }

    /// The workspace the UI is currently scoped to (persisted across launches).
    static func currentWorkspace(in context: ModelContext) throws -> Workspace? {
        guard
            let raw = UserDefaults.standard.string(forKey: workspaceDefaultsKey),
            let id = UUID(uuidString: raw)
        else { return nil }
        let descriptor = FetchDescriptor<Workspace>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
        )
        return try context.fetch(descriptor).first
    }

    static func select(workspace: Workspace) {
        UserDefaults.standard.set(workspace.id.uuidString, forKey: workspaceDefaultsKey)
    }

    // MARK: Internals

    /// L'utente locale: se il profilo non esiste ancora (primo avvio assoluto)
    /// nasce dal nome utente del sistema — niente identità hard-coded (D49).
    private static func currentUser(in context: ModelContext) throws -> UserProfile {
        let users = try context.fetch(
            FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        )
        let savedID = UserDefaults.standard.string(forKey: userDefaultsKey)
            .flatMap(UUID.init(uuidString:))
        if let user = users.first(where: { $0.id == savedID && $0.deletedAt == nil })
            ?? users.first(where: { $0.deletedAt == nil }) {
            return user
        }
        #if os(macOS)
        let name = NSFullUserName()
        #else
        let name = "Io"
        #endif
        let me = UserProfile(name: name.isEmpty ? "Io" : name, email: "", isLocalSeed: true)
        context.insert(me)
        return me
    }

    private static func ensureMemberships(for user: UserProfile, in context: ModelContext) throws {
        let workspaces = try context.fetch(FetchDescriptor<Workspace>())
        let memberships = try context.fetch(FetchDescriptor<Membership>())
        for workspace in workspaces where workspace.deletedAt == nil {
            let exists = memberships.contains {
                $0.workspaceID == workspace.id && $0.userID == user.id && $0.deletedAt == nil
            }
            if !exists {
                context.insert(Membership(workspaceID: workspace.id, userID: user.id, role: .owner))
            }
        }
    }

    /// Due dispositivi possono fare il primo seed PRIMA che CloudKit unisca i
    /// dati → workspace e profili doppi. Qui si fondono: vince il più vecchio,
    /// tutto il contenuto del doppione viene ripuntato, il doppione sparisce.
    ///
    /// Audit A1 (2026-09-10): la dedupe fondeva per nome QUALSIASI coppia di
    /// spazi/profili — due aziende diverse chiamate uguale, o due compagni di
    /// team omonimi, venivano unite ed eliminate senza che l'utente lo
    /// chiedesse. Ora si fonde SOLO ciò che il seed genera da sé: lo spazio
    /// "Personale" (`isPersonal`, nome fisso, mai scelto dall'utente) e il
    /// profilo "me" auto-generato (`isLocalSeed`, vedi V10) — mai uno spazio o
    /// una persona che l'utente ha creato o aggiunto a mano.
    private static func dedupeAfterCloudMerge(in context: ModelContext) throws {
        // Solo lo spazio Personale: è un singleton generato dal seed, non un
        // nome scelto dall'utente — due "Personale" sono davvero lo stesso
        // spazio visto da due dispositivi prima del merge CloudKit.
        let personalWorkspaces = try context.fetch(
            FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.createdAt)])
        ).filter { $0.deletedAt == nil && $0.isPersonal }
        if personalWorkspaces.count > 1 {
            let keeper = personalWorkspaces[0]
            for duplicate in personalWorkspaces.dropFirst() {
                try repointWorkspace(from: duplicate.id, to: keeper.id, in: context)
                duplicate.deletedAt = .now
                duplicate.updatedAt = .now
            }
        }

        // Solo i profili "me" auto-generati (stesso identikit di dispositivo,
        // niente identità reale da confrontare): mai un profilo aggiunto a
        // mano da Team, anche se condivide il nome.
        let seedProfiles = try context.fetch(
            FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        ).filter { $0.deletedAt == nil && $0.isLocalSeed }
        let profileGroups = Dictionary(grouping: seedProfiles) { $0.name.lowercased() }
        for (_, group) in profileGroups where group.count > 1 {
            let keeper = group[0]
            for duplicate in group.dropFirst() {
                try repointUser(from: duplicate.id, to: keeper.id, in: context)
                duplicate.deletedAt = .now
                duplicate.updatedAt = .now
            }
        }
    }

    private static func repointWorkspace(
        from old: UUID, to new: UUID, in context: ModelContext
    ) throws {
        for task in try context.fetch(FetchDescriptor<TodoTask>())
        where task.workspaceID == old { task.workspaceID = new }
        for project in try context.fetch(FetchDescriptor<Project>())
        where project.workspaceID == old { project.workspaceID = new }
        for tag in try context.fetch(FetchDescriptor<Tag>())
        where tag.workspaceID == old { tag.workspaceID = new }
        for stage in try context.fetch(FetchDescriptor<WorkflowStage>())
        where stage.workspaceID == old { stage.workspaceID = new }
        for rule in try context.fetch(FetchDescriptor<AutomationRule>())
        where rule.workspaceID == old { rule.workspaceID = new }
        for field in try context.fetch(FetchDescriptor<CustomFieldDefinition>())
        where field.workspaceID == old { field.workspaceID = new }
        for value in try context.fetch(FetchDescriptor<CustomFieldValue>())
        where value.workspaceID == old { value.workspaceID = new }
        for view in try context.fetch(FetchDescriptor<SavedView>())
        where view.workspaceID == old { view.workspaceID = new }
        for attachment in try context.fetch(FetchDescriptor<Attachment>())
        where attachment.workspaceID == old { attachment.workspaceID = new }
        for dependency in try context.fetch(FetchDescriptor<TaskDependency>())
        where dependency.workspaceID == old { dependency.workspaceID = new }
        for membership in try context.fetch(FetchDescriptor<Membership>())
        where membership.workspaceID == old { membership.deletedAt = .now }
        // Lo scope/preferenze puntavano al doppione? Riallinea.
        if UserDefaults.standard.string(forKey: workspaceDefaultsKey) == old.uuidString {
            UserDefaults.standard.set(new.uuidString, forKey: workspaceDefaultsKey)
        }
    }

    private static func repointUser(
        from old: UUID, to new: UUID, in context: ModelContext
    ) throws {
        for task in try context.fetch(FetchDescriptor<TodoTask>()) {
            if task.createdByID == old { task.createdByID = new }
            if task.assigneeID == old { task.assigneeID = new }
            if task.delegatedByID == old { task.delegatedByID = new }
        }
        for project in try context.fetch(FetchDescriptor<Project>())
        where project.createdByID == old { project.createdByID = new }
        for rule in try context.fetch(FetchDescriptor<AutomationRule>()) {
            if rule.createTaskAssigneeID == old { rule.createTaskAssigneeID = new }
            if rule.assignToID == old { rule.assignToID = new }
            if rule.notifyUserID == old { rule.notifyUserID = new }
        }
        for membership in try context.fetch(FetchDescriptor<Membership>())
        where membership.userID == old { membership.deletedAt = .now }
        if UserDefaults.standard.string(forKey: userDefaultsKey) == old.uuidString {
            UserDefaults.standard.set(new.uuidString, forKey: userDefaultsKey)
        }
    }

    private static func persistDefaults(workspace: Workspace, user: UserProfile) {
        UserDefaults.standard.set(workspace.id.uuidString, forKey: workspaceDefaultsKey)
        UserDefaults.standard.set(user.id.uuidString, forKey: userDefaultsKey)
    }
}
