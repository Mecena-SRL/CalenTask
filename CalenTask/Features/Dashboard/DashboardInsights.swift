import SwiftUI
import SwiftData
import Charts

// F15 — il quadro statistico e i suggerimenti della pagina Oggi:
// l'andamento del lavoro (fatte/create per giorno) e uno spazio dedicato
// ai consigli per ottimizzare. F19 — la campanella degli aggiornamenti.

// MARK: - Andamento (F15)

struct DashboardTrendSection: View {
    @Query(filter: #Predicate<TodoTask> {
        $0.deletedAt == nil && !$0.isTemplate
    })
    private var allTasks: [TodoTask]

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"

    private var tasks: [TodoTask] {
        WorkspaceScope.filter(allTasks, raw: scopeRaw, id: \.workspaceID)
    }

    private var calendar: Calendar { .current }

    private struct DayCount: Identifiable {
        var id: Date { day }
        let day: Date
        let kind: String   // "Fatte" | "Create"
        let count: Int
    }

    private var window: [Date] {
        let today = calendar.startOfDay(for: .now)
        return (0..<14).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private var dayCounts: [DayCount] {
        var done: [Date: Int] = [:]
        var created: [Date: Int] = [:]
        for task in tasks {
            if let completedAt = task.completedAt {
                done[calendar.startOfDay(for: completedAt), default: 0] += 1
            }
            created[calendar.startOfDay(for: task.createdAt), default: 0] += 1
        }
        return window.flatMap { day in
            [
                DayCount(day: day, kind: "Fatte", count: done[day] ?? 0),
                DayCount(day: day, kind: "Create", count: created[day] ?? 0),
            ]
        }
    }

    /// Fatte negli ultimi 7 giorni vs i 7 precedenti.
    private var weeklyDelta: (current: Int, previous: Int) {
        let today = calendar.startOfDay(for: .now)
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: today),
              let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: today)
        else { return (0, 0) }
        let completions = tasks.compactMap(\.completedAt)
        let current = completions.count { $0 >= weekAgo }
        let previous = completions.count { $0 >= twoWeeksAgo && $0 < weekAgo }
        return (current, previous)
    }

    var body: some View {
        let delta = weeklyDelta
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Andamento", count: delta.current)
            VStack(alignment: .leading, spacing: DS.m) {
                HStack(spacing: DS.xl) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(delta.current)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())
                        Text("fatte negli ultimi 7 giorni")
                            .font(.dsCaption)
                            .foregroundStyle(.secondary)
                    }
                    if delta.previous > 0 || delta.current > 0 {
                        let diff = delta.current - delta.previous
                        Label(
                            diff == 0 ? "stabile" : "\(diff > 0 ? "+" : "")\(diff) vs settimana prima",
                            systemImage: diff > 0 ? "arrow.up.right"
                                : diff < 0 ? "arrow.down.right" : "equal"
                        )
                        .font(.dsCaption.weight(.semibold))
                        .foregroundStyle(diff >= 0 ? DSColor.status(.done) : DSColor.overdue)
                    }
                    Spacer()
                }

                Chart(dayCounts) { entry in
                    BarMark(
                        x: .value("Giorno", entry.day, unit: .day),
                        y: .value("Attività", entry.count)
                    )
                    .foregroundStyle(by: .value("Tipo", entry.kind))
                    .position(by: .value("Tipo", entry.kind))
                    .cornerRadius(2)
                }
                .chartForegroundStyleScale([
                    "Fatte": DSColor.status(.done),
                    "Create": Color.accentColor.opacity(0.45),
                ])
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.day(), centered: true)
                    }
                }
                .chartLegend(position: .bottom, spacing: DS.s)
                .frame(height: 120)
            }
            .padding(DS.l)
            .background(DSColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        }
    }
}

// MARK: - Suggerimenti (F15)

struct DashboardAdviceSection: View {
    let openTasks: [TodoTask]
    let inboxCount: Int
    let projects: [Project]

    @Environment(AppRouter.self) private var router

    private struct Advice: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let text: String
        var destination: AppSection?
    }

    private var calendar: Calendar { .current }

    private var advice: [Advice] {
        var result: [Advice] = []
        let today = calendar.startOfDay(for: .now)

        if inboxCount > 5 {
            result.append(Advice(
                icon: "tray.full", tint: AppSection.inbox.tint,
                text: "\(inboxCount) attività in Inbox: un giro di Smista le rimette al loro posto.",
                destination: .inbox
            ))
        }

        let overdue = openTasks.filter { ($0.dueAt ?? .distantFuture) < today }
        if overdue.count >= 3 {
            result.append(Advice(
                icon: "clock.arrow.circlepath", tint: DSColor.overdue,
                text: "\(overdue.count) attività in ritardo: riprogrammale o lascia andare quelle superate.",
                destination: .dashboard
            ))
        }

        let dateless = openTasks.filter {
            $0.dueAt == nil && $0.startAt == nil && $0.remindAt == nil
        }
        if dateless.count > 8 {
            result.append(Advice(
                icon: "calendar.badge.plus", tint: .teal,
                text: "\(dateless.count) attività senza data: dai loro un \"quando\" e usciranno dal limbo.",
                destination: .quick
            ))
        }

        let urgent = openTasks.filter { $0.priority == .urgent }
        if urgent.count > 5 {
            result.append(Advice(
                icon: "flag.fill", tint: DSColor.priority(.urgent),
                text: "\(urgent.count) attività urgenti aperte: se è tutto urgente, niente lo è davvero.",
                destination: .quick
            ))
        }

        // Progetti fermi: nessun movimento da 14 giorni.
        for project in projects {
            let live = project.tasks.filter { $0.deletedAt == nil && !$0.isDone }
            guard !live.isEmpty,
                  let lastTouch = live.map(\.updatedAt).max(),
                  let days = calendar.dateComponents([.day], from: lastTouch, to: .now).day,
                  days >= 14
            else { continue }
            result.append(Advice(
                icon: "zzz", tint: Color(hex: project.colorHex),
                text: "\"\(project.name)\" è fermo da \(days) giorni: rilancialo o archivialo.",
                destination: .projects
            ))
        }

        // Eventi back-to-back domani: serve respiro.
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            let events = openTasks
                .filter {
                    ($0.kind == .event || $0.kind == .shootDay)
                        && $0.startAt.map { calendar.isDate($0, inSameDayAs: tomorrow) } == true
                }
            if events.count >= 4 {
                result.append(Advice(
                    icon: "wind", tint: .blue,
                    text: "Domani hai \(events.count) eventi: tieniti dei buchi per respirare.",
                    destination: .calendar
                ))
            }
        }

        return Array(result.prefix(3))
    }

    var body: some View {
        let items = advice
        // D94 — widget sempre presente: anche senza consigli mostra una card,
        // così resta riposizionabile e nascondibile come gli altri.
        VStack(alignment: .leading, spacing: DS.s) {
            DSSectionHeader(title: "Suggerimenti", count: items.isEmpty ? nil : items.count)
            if items.isEmpty {
                Text("Nessun consiglio al momento: tutto in ordine. ✨")
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.l)
                    .background(DSColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        Button {
                            if let destination = item.destination {
                                router.go(destination)
                            }
                        } label: {
                            HStack(spacing: DS.m) {
                                DSIconTile(systemImage: item.icon, tint: item.tint)
                                Text(item.text)
                                    .font(.dsMeta)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if item.destination != nil {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, DS.m)
                            .padding(.vertical, DS.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if item.id != items.last?.id {
                            Divider().padding(.leading, DS.xxl + DS.s)
                        }
                    }
                }
                .padding(.vertical, DS.xs)
                .background(DSColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            }
        }
    }
}

// MARK: - Campanella aggiornamenti (F19)

struct NotificationsBellButton: View {
    @Query(filter: TodoTask.openPredicate)
    private var allOpenTasks: [TodoTask]

    @Query(filter: #Predicate<TodoTask> {
        $0.deletedAt == nil && !$0.isTemplate
    })
    private var allTasks: [TodoTask]

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    @State private var isOpen = false

    private var calendar: Calendar { .current }

    private var openTasks: [TodoTask] {
        WorkspaceScope.filter(allOpenTasks, raw: scopeRaw, id: \.workspaceID)
    }

    private var overdue: [TodoTask] {
        let today = calendar.startOfDay(for: .now)
        return openTasks
            .filter { ($0.dueAt ?? .distantFuture) < today }
            .sorted { ($0.dueAt ?? .now) < ($1.dueAt ?? .now) }
    }

    /// Promemoria nelle prossime 24 ore.
    private var imminent: [TodoTask] {
        let now = Date.now
        guard let dayAhead = calendar.date(byAdding: .day, value: 1, to: now)
        else { return [] }
        return openTasks
            .filter { task in
                guard let remindAt = task.remindAt else { return false }
                return remindAt >= now && remindAt <= dayAhead
            }
            .sorted { ($0.remindAt ?? .now) < ($1.remindAt ?? .now) }
    }

    /// Movimenti recenti (ultime 48h) — anche da altri dispositivi (CloudKit).
    private var recent: [TodoTask] {
        guard let cutoff = calendar.date(byAdding: .hour, value: -48, to: .now)
        else { return [] }
        return WorkspaceScope.filter(allTasks, raw: scopeRaw, id: \.workspaceID)
            .filter { $0.updatedAt >= cutoff && $0.updatedAt != $0.createdAt }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var badgeCount: Int {
        overdue.count + imminent.count
    }

    var body: some View {
        Button {
            isOpen = true
        } label: {
            Label("Notifiche", systemImage: badgeCount > 0 ? "bell.badge" : "bell")
                .symbolRenderingMode(badgeCount > 0 ? .multicolor : .monochrome)
        }
        .badge(badgeCount)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            content
                .frame(width: 320)
                .frame(maxHeight: 440)
        }
        .help("Aggiornamenti sulle attività")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.m) {
                Text("Aggiornamenti")
                    .font(.dsSectionTitle)

                if overdue.isEmpty && imminent.isEmpty && recent.isEmpty {
                    Text("Tutto tranquillo: nessun aggiornamento.")
                        .font(.dsMeta)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, DS.l)
                }

                if !overdue.isEmpty {
                    bellSection("In ritardo", tasks: Array(overdue.prefix(5)),
                                icon: "clock.arrow.circlepath", tint: DSColor.overdue) {
                        $0.dueAt?.dsRelativeLabel ?? ""
                    }
                }
                if !imminent.isEmpty {
                    bellSection("Promemoria in arrivo", tasks: Array(imminent.prefix(5)),
                                icon: "bell", tint: .purple) {
                        $0.remindAt.map { "\($0.dsRelativeLabel), \($0.dsTimeLabel)" } ?? ""
                    }
                }
                if !recent.isEmpty {
                    bellSection("Modificate di recente", tasks: Array(recent.prefix(5)),
                                icon: "arrow.triangle.2.circlepath", tint: .blue) {
                        $0.updatedAt.formatted(.relative(presentation: .named))
                    }
                }
            }
            .padding(DS.l)
        }
    }

    private func bellSection(
        _ title: String, tasks: [TodoTask],
        icon: String, tint: Color,
        detail: @escaping (TodoTask) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            Label(title, systemImage: icon)
                .font(.dsCaption.weight(.semibold))
                .foregroundStyle(tint)
            VStack(spacing: 0) {
                ForEach(tasks, id: \.id) { task in
                    TaskOpenLink(task: task) {
                        HStack(spacing: DS.s) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.title)
                                    .font(.dsMeta)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(detail(task))
                                    .font(.dsCaption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, DS.xs)
                        .contentShape(Rectangle())
                    }
                    .simultaneousGesture(TapGesture().onEnded { isOpen = false })
                }
            }
        }
    }
}

#Preview("Insights") {
    let preview = PreviewSampleData.make()
    return ScrollView {
        VStack(spacing: 24) {
            DashboardTrendSection()
            NotificationsBellButton()
        }
        .padding()
    }
    .environment(AppRouter())
    .modelContainer(preview.container)
}
