import SwiftUI
import SwiftData
import Charts

/// Riepilogo di progetto (D34): la dashboard del singolo progetto —
/// numeri chiave, distribuzione in pipeline, avanzamento fasi,
/// completamenti nel tempo, prossime scadenze.
struct ProjectSummaryView: View {
    @Bindable var project: Project

    @Query(filter: #Predicate<WorkflowStage> { $0.deletedAt == nil },
           sort: \WorkflowStage.order)
    private var allStages: [WorkflowStage]

    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil },
           sort: \UserProfile.createdAt)
    private var people: [UserProfile]

    private var stages: [WorkflowStage] {
        allStages.filter { $0.projectID == project.id }
    }

    private var liveTasks: [TodoTask] {
        project.tasks.filter { $0.deletedAt == nil && !$0.isPhase && !$0.isTemplate }
    }

    /// G4 — il riepilogo segue lo spazio: testata e numeri a tutta
    /// larghezza, poi due colonne quando lo schermo le regge.
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.xl) {
                headerCard
                statTiles

                if contentWidth >= 980 {
                    HStack(alignment: .top, spacing: DS.xl) {
                        VStack(alignment: .leading, spacing: DS.xl) {
                            structureSections
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: DS.xl) {
                            analyticsSections
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    structureSections
                    analyticsSections
                }
            }
            .padding(DS.l)
        }
        .background(DSColor.surfaceSecondary)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            contentWidth = width
        }
    }

    /// La struttura del lavoro: pipeline, fasi, prossime scadenze.
    @ViewBuilder
    private var structureSections: some View {
        if !stages.isEmpty {
            pipelineSection
        }
        if !project.phaseTasks.isEmpty {
            phasesSection
        }
        if !upcoming.isEmpty {
            upcomingSection
        }
    }

    /// I numeri nel tempo: persone, durate, completamenti.
    @ViewBuilder
    private var analyticsSections: some View {
        if !contributorSlices.isEmpty {
            contributorsSection
        }
        if !phaseStats.isEmpty {
            phaseTimeSection
        }
        completionSection
    }

    // MARK: Testata (F33) — l'avanzamento e l'orizzonte a colpo d'occhio

    private var progress: Double {
        liveTasks.isEmpty ? 0 : Double(doneTasks.count) / Double(liveTasks.count)
    }

    private var lastDeadline: Date? {
        liveTasks.compactMap(\.dueAt).max() ?? project.dueDate
    }

    private var headerCard: some View {
        let tint = Color(hex: project.colorHex)
        return HStack(spacing: DS.xl) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.dsNumeric.weight(.bold))
            }
            .frame(width: 72, height: 72)
            .animation(.dsSoft, value: progress)

            VStack(alignment: .leading, spacing: DS.xs) {
                Text("\(doneTasks.count) fatte su \(liveTasks.count)")
                    .font(.dsMeta.weight(.semibold))
                HStack(spacing: DS.l) {
                    if let lastDeadline {
                        let days = Calendar.current.dateComponents(
                            [.day], from: .now, to: lastDeadline
                        ).day ?? 0
                        Label(
                            days >= 0 ? "\(days) giorni all'ultima scadenza"
                                      : "ultima scadenza superata da \(-days) giorni",
                            systemImage: "flag.checkered"
                        )
                        .foregroundStyle(days >= 0 ? Color.secondary : DSColor.overdue)
                    }
                    if !project.phaseTasks.isEmpty {
                        Label("\(project.phaseTasks.count) fasi",
                              systemImage: "square.stack.3d.up")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.dsCaption)
                // S6/D64 — lo Smart Status anche qui, nel quadro generale.
                let status = project.smartStatus
                Text(status.label)
                    .font(.dsCaption.weight(.semibold))
                    .padding(.horizontal, DS.s)
                    .padding(.vertical, 2)
                    .background(status.color.opacity(0.14), in: Capsule())
                    .foregroundStyle(status.color)
            }
            Spacer()
        }
        .padding(DS.l)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
    }

    // MARK: Numeri chiave

    private var statTiles: some View {
        // G4 — adattive: 4 in fila col respiro giusto, 2×2 quando serve.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 400), spacing: DS.m)],
            spacing: DS.m
        ) {
            StatTile(
                title: "Aperte", count: openTasks.count,
                icon: "circle", tint: Color(hex: project.colorHex)
            )
            StatTile(
                title: "Completate", count: doneTasks.count,
                icon: "checkmark.circle", tint: DSColor.status(.done)
            )
            StatTile(
                title: "In ritardo", count: overdueTasks.count,
                icon: "exclamationmark.circle", tint: DSColor.overdue
            )
            StatTile(
                title: "Bloccate", count: blockedTasks.count,
                icon: "hand.raised", tint: DSColor.status(.blocked)
            )
        }
    }

    // MARK: Pipeline

    private struct StageSlice: Identifiable {
        let id = UUID()
        let stage: String
        let colorHex: String
        let count: Int
    }

    private var pipelineSlices: [StageSlice] {
        var result = stages.map { stage in
            StageSlice(
                stage: stage.name, colorHex: stage.colorHex,
                count: liveTasks.filter { $0.stageID == stage.id }.count
            )
        }
        let stageIDs = Set(stages.map(\.id))
        let unstaged = liveTasks.filter {
            $0.stageID == nil || !stageIDs.contains($0.stageID!)
        }.count
        if unstaged > 0 {
            result.insert(StageSlice(stage: "Da smistare", colorHex: "#94A3B8", count: unstaged), at: 0)
        }
        return result
    }

    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Pipeline", count: liveTasks.count)
            Chart(pipelineSlices) { slice in
                BarMark(
                    x: .value("Attività", slice.count),
                    y: .value("Stage", slice.stage)
                )
                .foregroundStyle(Color(hex: slice.colorHex).gradient)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    if slice.count > 0 {
                        Text("\(slice.count)")
                            .font(.dsCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(preset: .aligned) { _ in
                    AxisValueLabel().font(.dsCaption)
                }
            }
            .frame(height: max(140, CGFloat(pipelineSlices.count) * 30))
            .padding(DS.l)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
    }

    // MARK: Fasi

    private var phasesSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Avanzamento fasi", count: project.phaseTasks.count)
            VStack(spacing: DS.m) {
                ForEach(project.phaseTasks, id: \.id) { phase in
                    let children = phase.liveSubtasks.filter { !$0.isTemplate }
                    HStack(spacing: DS.m) {
                        Text(phase.title)
                            .font(.dsMeta)
                            .frame(width: 170, alignment: .leading)
                            .lineLimit(1)
                        ProgressView(value: phase.aggregatedProgress)
                            .tint(Color(hex: project.colorHex))
                        Text("\(children.filter(\.isDone).count)/\(children.count)")
                            .font(.dsNumeric)
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
            .padding(DS.l)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
    }

    // MARK: Chi ha fatto di più (D40)

    private struct ContributorSlice: Identifiable {
        let id = UUID()
        let person: String
        let done: Int
        let open: Int
    }

    private var contributorSlices: [ContributorSlice] {
        var slices = people.compactMap { person -> ContributorSlice? in
            let mine = liveTasks.filter { $0.assigneeID == person.id }
            guard !mine.isEmpty else { return nil }
            return ContributorSlice(
                person: person.name,
                done: mine.filter(\.isDone).count,
                open: mine.filter { !$0.isDone }.count
            )
        }
        let unassigned = liveTasks.filter { $0.assigneeID == nil }
        if !unassigned.isEmpty, !slices.isEmpty {
            slices.append(ContributorSlice(
                person: "Non assegnate",
                done: unassigned.filter(\.isDone).count,
                open: unassigned.filter { !$0.isDone }.count
            ))
        }
        return slices.sorted { $0.done > $1.done }
    }

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Chi ha fatto di più", count: contributorSlices.count)
            Chart {
                ForEach(contributorSlices) { slice in
                    BarMark(
                        x: .value("Attività", slice.done),
                        y: .value("Persona", slice.person)
                    )
                    .foregroundStyle(DSColor.status(.done).gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text("\(slice.done) fatte · \(slice.open) aperte")
                            .font(.dsCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(preset: .aligned) { _ in
                    AxisValueLabel().font(.dsCaption)
                }
            }
            .frame(height: max(80, CGFloat(contributorSlices.count) * 36))
            .padding(DS.l)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
    }

    // MARK: Tempo e volume per fase (D40)

    private struct PhaseStat: Identifiable {
        let id: UUID
        let name: String
        let days: Int
        let taskCount: Int
        let doneCount: Int
    }

    private var phaseStats: [PhaseStat] {
        let calendar = Calendar.current
        return project.phaseTasks.compactMap { phase in
            let children = phase.liveSubtasks.filter { !$0.isTemplate }
            guard !children.isEmpty else { return nil }
            let spans: [(Date, Date)] = children.compactMap { task in
                let start = task.startAt ?? task.dueAt
                let end = task.endAt ?? task.dueAt ?? task.startAt
                guard let start, let end else { return nil }
                return (min(start, end), max(start, end))
            }
            let days: Int
            if let minDate = spans.map(\.0).min(), let maxDate = spans.map(\.1).max() {
                days = (calendar.dateComponents([.day], from: minDate, to: maxDate).day ?? 0) + 1
            } else {
                days = 0
            }
            return PhaseStat(
                id: phase.id, name: phase.title, days: days,
                taskCount: children.count, doneCount: children.filter(\.isDone).count
            )
        }
        .sorted { $0.days > $1.days }
    }

    private var phaseTimeSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Tempo per fase", count: phaseStats.count)
            Chart(phaseStats) { stat in
                BarMark(
                    x: .value("Giorni", max(stat.days, 1)),
                    y: .value("Fase", stat.name)
                )
                .foregroundStyle(Color(hex: project.colorHex).gradient)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text(stat.days > 0
                         ? "\(stat.days)g · \(stat.doneCount)/\(stat.taskCount) task"
                         : "\(stat.doneCount)/\(stat.taskCount) task")
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(preset: .aligned) { _ in
                    AxisValueLabel().font(.dsCaption)
                }
            }
            .frame(height: max(80, CGFloat(phaseStats.count) * 36))
            .padding(DS.l)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
    }

    // MARK: Completamenti per settimana

    private struct WeekPoint: Identifiable {
        let id = UUID()
        let week: Date
        let count: Int
    }

    private var completionPoints: [WeekPoint] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .weekOfYear, value: -7, to: .now.startOfDay)!
        var buckets: [Date: Int] = [:]
        for task in doneTasks where task.updatedAt >= start {
            let week = calendar.dateInterval(of: .weekOfYear, for: task.updatedAt)?.start
                ?? task.updatedAt.startOfDay
            buckets[week, default: 0] += 1
        }
        return (0..<8).compactMap { offset in
            guard let week = calendar.date(byAdding: .weekOfYear, value: offset - 7, to: .now),
                  let weekStart = calendar.dateInterval(of: .weekOfYear, for: week)?.start
            else { return nil }
            return WeekPoint(week: weekStart, count: buckets[weekStart] ?? 0)
        }
    }

    private var completionSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Completate per settimana", count: doneTasks.count)
            Chart(completionPoints) { point in
                AreaMark(
                    x: .value("Settimana", point.week, unit: .weekOfYear),
                    y: .value("Completate", point.count)
                )
                .foregroundStyle(Color(hex: project.colorHex).opacity(0.18).gradient)
                LineMark(
                    x: .value("Settimana", point.week, unit: .weekOfYear),
                    y: .value("Completate", point.count)
                )
                .foregroundStyle(Color(hex: project.colorHex))
                .symbol(.circle)
            }
            .frame(height: 140)
            .padding(DS.l)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
    }

    // MARK: Prossime scadenze

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Prossime scadenze", count: upcoming.count)
            VStack(spacing: 0) {
                ForEach(upcoming.prefix(5), id: \.id) { task in
                    TaskOpenLink(task: task) {
                        TaskRow(task: task, showProject: false) {
                            withAnimation(.dsSoft) { task.toggleDone() }
                        }
                    }
                    .padding(.horizontal, DS.m)
                }
            }
            .padding(.vertical, DS.s)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
    }

    // MARK: Grouping

    private var openTasks: [TodoTask] { liveTasks.filter { !$0.isDone } }
    private var doneTasks: [TodoTask] { liveTasks.filter(\.isDone) }
    private var overdueTasks: [TodoTask] { liveTasks.filter(\.isOverdue) }
    private var blockedTasks: [TodoTask] { liveTasks.filter { $0.status == .blocked } }

    private var upcoming: [TodoTask] {
        openTasks
            .filter { $0.dueAt != nil }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return NavigationStack {
        ProjectSummaryView(project: preview.project)
    }
    .modelContainer(preview.container)
}
