import SwiftUI
import Foundation

// Provenienza + organizzazione dell'Inbox (v8): rendere visibile DA DOVE arriva
// ogni task (chi l'ha catturato/chiesto/assegnato, in quale spazio) e dargli un
// posto chiaro per data e per origine. Tutta la logica di derivazione vive qui,
// le viste la mostrano soltanto.

/// Descrittore calcolato della provenienza di un task, pronto per la riga.
struct TaskProvenance: Equatable {
    let label: String
    let detail: String?
    let systemImage: String
    let tint: Color
    /// Se valorizzato, la riga mostra le iniziali della persona invece dell'icona.
    let personName: String?
    /// Spazio non personale a cui appartiene il task (badge organizzazione).
    let workspaceName: String?

    static let captureTint = Color.secondary
}

extension TodoTask {
    /// Calcola la provenienza risolvendo gli UUID con mappe precostruite
    /// (`people` id→nome, `workspaces` id→Workspace) — niente fetch per riga.
    /// `meID` distingue "catturata da te" da "da X".
    func provenance(
        meID: UUID?,
        people: [UUID: String],
        workspaces: [UUID: Workspace]
    ) -> TaskProvenance {
        let workspace = workspaces[workspaceID]
        let workspaceName = (workspace?.isPersonal == false) ? workspace?.name : nil

        // 1. Richiesta esterna — chi l'ha chiesta.
        if isExternalRequest {
            let who = requesterName.isEmpty ? "Esterna" : requesterName
            return TaskProvenance(
                label: "Richiesta", detail: who,
                systemImage: "envelope.arrow.triangle.branch",
                tint: Color(hex: "#FFB224"),
                personName: nil, workspaceName: workspaceName
            )
        }
        // 2. Da prendere dal team (self-assign).
        if isClaimable {
            return TaskProvenance(
                label: "Da prendere", detail: "Team",
                systemImage: "hand.raised",
                tint: Color(hex: "#12A594"),
                personName: nil, workspaceName: workspaceName
            )
        }
        // 3. Delegata a me da qualcuno (si accende col multi-utente, v8+).
        if let by = delegatedByID, by != meID {
            let name = people[by] ?? "Team"
            return TaskProvenance(
                label: "Delegata", detail: "da \(name)",
                systemImage: "arrow.turn.down.right",
                tint: Color(hex: "#6E56CF"),
                personName: name, workspaceName: workspaceName
            )
        }
        // 4. Assegnata a un'altra persona.
        if let to = assigneeID, to != meID {
            let name = people[to] ?? "Team"
            return TaskProvenance(
                label: "Assegnata", detail: "a \(name)",
                systemImage: "person.crop.circle.badge.checkmark",
                tint: Color(hex: "#6E56CF"),
                personName: name, workspaceName: workspaceName
            )
        }
        // 5. Generata da un'automazione.
        if source == .automation {
            return TaskProvenance(
                label: "Automazione", detail: nil,
                systemImage: "gearshape.2",
                tint: TaskProvenance.captureTint,
                personName: nil, workspaceName: workspaceName
            )
        }
        // 6. Cattura rapida (il caso di gran lunga più comune): calmo, grigio.
        let mine = createdByID == meID
        let who = mine ? "da te" : people[createdByID].map { "da \($0)" }
        return TaskProvenance(
            label: "Cattura", detail: who,
            systemImage: "sparkles",
            tint: TaskProvenance.captureTint,
            personName: mine ? nil : people[createdByID],
            workspaceName: workspaceName
        )
    }
}

// MARK: - Etichetta provenienza (riga + carta di triage)

/// Riga compatta di provenienza: badge (icona o iniziali) + origine + dettaglio,
/// con un eventuale chip dello spazio quando il task non è personale.
struct ProvenanceLabel: View {
    let provenance: TaskProvenance

    private var text: String {
        if let detail = provenance.detail { "\(provenance.label) · \(detail)" }
        else { provenance.label }
    }

    var body: some View {
        HStack(spacing: DS.xs + 2) {
            badge
            Text(text)
                .font(.dsCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let workspace = provenance.workspaceName {
                workspaceChip(workspace)
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let name = provenance.personName, let initials = Self.initials(name) {
            Text(initials)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(provenance.tint.gradient, in: Circle())
        } else {
            Image(systemName: provenance.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(provenance.tint)
                .frame(width: 17, height: 17)
                .background(provenance.tint.opacity(0.14), in: Circle())
        }
    }

    private func workspaceChip(_ name: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 8))
            Text(name)
                .font(.dsCaption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, DS.xs + 1)
        .padding(.vertical, 1)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }

    static func initials(_ name: String) -> String? {
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first)
        let result = String(parts).uppercased()
        return result.isEmpty ? nil : result
    }
}

// MARK: - Filtro per origine

/// L'asse "categorizzazione" dell'Inbox: per origine. Affianca le sezioni
/// per data senza sostituirle.
enum InboxFilter: String, CaseIterable, Identifiable {
    case all, mine, requests, assigned, team

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "Tutto"
        case .mine: "Mie"
        case .requests: "Richieste"
        case .assigned: "Assegnate"
        case .team: "Dal team"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .mine: "person"
        case .requests: "envelope"
        case .assigned: "person.2"
        case .team: "hand.raised"
        }
    }

    func matches(_ task: TodoTask, meID: UUID?) -> Bool {
        switch self {
        case .all:
            return true
        case .mine:
            let assignedAway = task.assigneeID != nil && task.assigneeID != meID
            let delegatedToMe = task.delegatedByID != nil && task.delegatedByID != meID
            return !task.isExternalRequest && !task.isClaimable
                && !assignedAway && !delegatedToMe
        case .requests:
            return task.isExternalRequest
        case .assigned:
            let assignedAway = task.assigneeID != nil && task.assigneeID != meID
            let delegatedToMe = task.delegatedByID != nil && task.delegatedByID != meID
            return assignedAway || delegatedToMe
        case .team:
            return task.isClaimable
        }
    }
}

// MARK: - Raggruppamento per data

/// L'asse "semplificazione per data": quattro fasce sulla data di cattura.
enum InboxDateBucket: Int, CaseIterable, Identifiable {
    case today, yesterday, lastWeek, earlier

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: "Oggi"
        case .yesterday: "Ieri"
        case .lastWeek: "Ultimi 7 giorni"
        case .earlier: "Prima"
        }
    }

    static func bucket(for date: Date, now: Date = .now, calendar: Calendar = .current) -> InboxDateBucket {
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        let startOfToday = calendar.startOfDay(for: now)
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday),
           date >= weekAgo {
            return .lastWeek
        }
        return .earlier
    }
}
