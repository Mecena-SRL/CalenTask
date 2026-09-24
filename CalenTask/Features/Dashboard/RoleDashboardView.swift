import SwiftUI
import SwiftData

/// Dashboard per ruolo (D35): ogni persona vede il SUO cruscotto.
/// v1 sui segnali disponibili: stati, scadenze, assegnazioni, fasi,
/// parole chiave/#etichette (fattura, bando, materiali, permessi…).
enum DashboardRole: String, CaseIterable, Identifiable {
    case full, owner, preproduction, collaborator

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: "Completa"
        case .owner: "Direzione (Ivan)"
        case .preproduction: "Pre-produzione (Eleonora)"
        case .collaborator: "Collaboratore"
        }
    }

    var systemImage: String {
        switch self {
        case .full: "rectangle.grid.2x2"
        case .owner: "crown"
        case .preproduction: "doc.text.magnifyingglass"
        case .collaborator: "person"
        }
    }
}

struct RoleDashboardView: View {
    let role: DashboardRole
    let openTasks: [TodoTask]
    let projects: [Project]
    let people: [UserProfile]
    let configuration: AppConfiguration
    /// Collaboratore: di chi è il cruscotto.
    @Binding var collaboratorID: UUID?

    private var calendar: Calendar { .current }
    private var today: Date { .now.startOfDay }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.xl) {
            switch role {
            case .full:
                EmptyView()
            case .owner:
                ownerBoard
            case .preproduction:
                preproductionBoard
            case .collaborator:
                collaboratorBoard
            }
        }
    }

    // MARK: Direzione (Ivan) — D35

    @ViewBuilder
    private var ownerBoard: some View {
        criticalProjectsSection
        roleTaskSection("Scadenze della settimana", tasks: weekDeadlines,
                        icon: "calendar.badge.exclamationmark", tint: .orange)
        roleTaskSection("Task bloccate", tasks: blocked,
                        icon: "hand.raised", tint: DSColor.status(.blocked))
        roleTaskSection("Fatture da emettere", tasks: matching(["fattur"]),
                        icon: "eurosign.circle", tint: .green)
        if configuration.isEnabled(.production) {
            roleTaskSection("Carico post-produzione", tasks: postProduction,
                            icon: "film.stack", tint: .purple)
        }
        roleTaskSection("Consegne clienti", tasks: matching(["consegna", "delivery", "export"]),
                        icon: "shippingbox", tint: .blue)
    }

    private var criticalProjectsSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Progetti critici", count: criticalProjects.count,
                            tint: DSColor.overdue)
            if criticalProjects.isEmpty {
                quietNote("Nessun progetto in sofferenza. 🎬")
            } else {
                VStack(spacing: DS.s) {
                    ForEach(criticalProjects, id: \.project.id) { item in
                        NavigationLink {
                            ProjectDetailView(project: item.project)
                        } label: {
                            HStack(spacing: DS.m) {
                                Circle()
                                    .fill(Color(hex: item.project.colorHex))
                                    .frame(width: 10, height: 10)
                                Text(item.project.name)
                                    .font(.dsMeta.weight(.semibold))
                                Spacer()
                                if item.overdue > 0 {
                                    badge("\(item.overdue) in ritardo", tint: DSColor.overdue)
                                }
                                if item.blocked > 0 {
                                    badge("\(item.blocked) bloccate", tint: DSColor.status(.blocked))
                                }
                            }
                            .padding(DS.m)
                            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.small))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Pre-produzione (Eleonora) — D35

    @ViewBuilder
    private var preproductionBoard: some View {
        openPreproductionsSection
        roleTaskSection("Documenti mancanti", tasks: matching(["document", "liberator", "contratt"]),
                        icon: "doc.badge.ellipsis", tint: .orange)
        roleTaskSection("Contatti da sollecitare", tasks: matching(["contatt", "sollecit", "chiama"]),
                        icon: "phone.arrow.up.right", tint: .teal)
        roleTaskSection("Bandi in scadenza", tasks: matching(["bando", "bandi"]).filter { $0.dueAt != nil },
                        icon: "doc.text.below.ecg", tint: .indigo)
        roleTaskSection("Materiali da raccogliere", tasks: matching(["material", "attrezz", "noleggi"]),
                        icon: "shippingbox.and.arrow.backward", tint: .brown)
        roleTaskSection("Permessi e liberatorie", tasks: matching(["permess", "liberator", "occupazion"]),
                        icon: "checkmark.shield", tint: .green)
    }

    private var openPreproductionsSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Pre-produzioni aperte", count: openPreproductions.count)
            if openPreproductions.isEmpty {
                quietNote("Nessuna pre-produzione in corso.")
            } else {
                VStack(spacing: DS.s) {
                    ForEach(openPreproductions, id: \.id) { phase in
                        HStack(spacing: DS.m) {
                            Text(phase.project?.name ?? "—")
                                .font(.dsCaption)
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .leading)
                                .lineLimit(1)
                            Text(phase.title)
                                .font(.dsMeta)
                                .lineLimit(1)
                            Spacer()
                            ProgressView(value: phase.aggregatedProgress)
                                .frame(width: 80)
                                .tint(phase.project.map { Color(hex: $0.colorHex) } ?? .accentColor)
                        }
                        .padding(DS.m)
                        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.small))
                    }
                }
            }
        }
    }

    // MARK: Collaboratore — D35

    @ViewBuilder
    private var collaboratorBoard: some View {
        Picker("Persona", selection: $collaboratorID) {
            ForEach(people, id: \.id) { person in
                Text(person.name).tag(person.id as UUID?)
            }
        }
        .pickerStyle(.segmented)

        let mine = openTasks.filter { $0.assigneeID == collaboratorID }
        roleTaskSection("Le mie task", tasks: mine.filter { $0.dueAt == nil },
                        icon: "person.crop.circle", tint: .blue)
        roleTaskSection("Scadenze assegnate",
                        tasks: mine.filter { $0.dueAt != nil }
                            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) },
                        icon: "calendar", tint: .orange)
        roleTaskSection("Prendibili dal team", tasks: openTasks.filter(\.isClaimable),
                        icon: "hand.raised", tint: .teal)
        roleTaskSection("In approvazione", tasks: approvals(for: collaboratorID),
                        icon: "checkmark.seal", tint: .purple)
        myProjectsSection(mine: mine)
    }

    private func myProjectsSection(mine: [TodoTask]) -> some View {
        let myProjects = Array(
            Dictionary(grouping: mine.compactMap(\.project), by: \.id).values
        ).compactMap(\.first)
        return VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "I miei progetti", count: myProjects.count)
            if myProjects.isEmpty {
                quietNote("Nessun progetto assegnato.")
            } else {
                VStack(spacing: DS.s) {
                    ForEach(myProjects, id: \.id) { project in
                        NavigationLink {
                            ProjectDetailView(project: project)
                        } label: {
                            HStack(spacing: DS.m) {
                                Circle()
                                    .fill(Color(hex: project.colorHex))
                                    .frame(width: 10, height: 10)
                                Text(project.name)
                                    .font(.dsMeta.weight(.medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.dsCaption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(DS.m)
                            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.small))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Data slices

    private var criticalProjects: [(project: Project, overdue: Int, blocked: Int)] {
        projects.compactMap { project in
            let live = openTasks.filter { $0.project?.id == project.id }
            let overdue = live.filter(\.isOverdue).count
            let blocked = live.filter { $0.status == .blocked }.count
            guard overdue > 0 || blocked > 1 else { return nil }
            return (project, overdue, blocked)
        }
        .sorted { ($0.overdue, $0.blocked) > ($1.overdue, $1.blocked) }
    }

    private var weekDeadlines: [TodoTask] {
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) else { return [] }
        return openTasks
            .filter { task in
                guard let dueAt = task.dueAt else { return false }
                return dueAt >= today && dueAt < weekEnd
            }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    private var blocked: [TodoTask] {
        openTasks.filter { $0.status == .blocked }
    }

    private var postProduction: [TodoTask] {
        openTasks.filter { task in
            guard let phase = task.phaseAncestor else { return false }
            return phase.title.localizedCaseInsensitiveContains("post")
        }
    }

    private var openPreproductions: [TodoTask] {
        projects.flatMap(\.phaseTasks).filter { phase in
            phase.title.localizedCaseInsensitiveContains("pre-produzione")
                && phase.aggregatedProgress < 1
        }
    }

    private func approvals(for personID: UUID?) -> [TodoTask] {
        openTasks.filter { task in
            guard task.assigneeID == personID else { return false }
            return task.title.localizedCaseInsensitiveContains("approv")
                || task.title.localizedCaseInsensitiveContains("revision")
                || task.parsedTagNames.contains { $0.contains("approv") }
        }
    }

    /// Keyword/#tag matcher: il v1 onesto dei "report automatici" (D35).
    private func matching(_ keywords: [String]) -> [TodoTask] {
        openTasks.filter { task in
            keywords.contains { keyword in
                task.title.localizedCaseInsensitiveContains(keyword)
                    || task.parsedTagNames.contains { $0.contains(keyword) }
            }
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private func roleTaskSection(
        _ title: String, tasks: [TodoTask], icon: String, tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.s) {
            HStack(spacing: DS.s) {
                Image(systemName: icon)
                    .font(.dsCaption.weight(.semibold))
                    .foregroundStyle(tint)
                DSSectionHeader(title: title, count: tasks.count, tint: tint)
            }
            if tasks.isEmpty {
                quietNote("Niente qui. ✓")
            } else {
                VStack(spacing: 0) {
                    ForEach(tasks.prefix(6), id: \.id) { task in
                        TaskOpenLink(task: task) {
                            TaskRow(task: task) {
                                withAnimation(.dsSoft) { task.toggleDone() }
                            }
                        }
                        .taskContextMenu(task)
                        .padding(.horizontal, DS.m)
                        if task.id != tasks.prefix(6).last?.id {
                            Divider().padding(.leading, DS.xxl + DS.s)
                        }
                    }
                }
                .padding(.vertical, DS.s)
                .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            }
        }
    }

    private func quietNote(_ text: String) -> some View {
        Text(text)
            .font(.dsCaption)
            .foregroundStyle(.secondary)
            .padding(DS.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: DS.Radius.small))
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.dsCaption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.s)
            .padding(.vertical, 2)
            .background(tint, in: Capsule())
    }
}
