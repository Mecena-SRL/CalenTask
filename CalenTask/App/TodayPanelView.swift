import SwiftUI
import SwiftData
import Combine

/// Costanti del pannello Oggi (D74), condivise tra shell e menu macOS.
enum TodayPanel {
    static let storageKey = "showsTodayPanel"
    /// Sotto questa larghezza il pannello cede il passo al contenuto:
    /// sidebar (~240) + sezione comoda (~680) + pannello (~320).
    static let minimumShellWidth: CGFloat = 1240
}

/// D74 — il pannello del giorno: la colonna destra che appare quando la
/// finestra ha spazio (un 27"/32" la tiene sempre). Qualunque sezione tu
/// stia guardando, il polso della giornata resta in vista: agenda,
/// scadenze, inbox, domani.
///
/// #5 — L'involucro sceglie spazio e giorno; il contenuto carica dallo
/// store solo oggi, domani e le scadute, non tutte le attività aperte.
struct TodayPanelView: View {
    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    /// Si aggiorna a mezzanotte: il pannello non resta su "ieri".
    @State private var today = Calendar.current.startOfDay(for: .now)

    /// La X c'è solo dove esiste un modo per riaprire (menu Vista, macOS).
    var onClose: (() -> Void)?

    var body: some View {
        TodayPanelContent(
            workspaceID: WorkspaceScope.workspaceID(raw: scopeRaw), today: today, onClose: onClose
        )
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = Calendar.current.startOfDay(for: .now)
        }
    }
}

private struct TodayPanelContent: View {
    @Environment(AppRouter.self) private var router

    @Query private var starting: [TodoTask]
    @Query private var due: [TodoTask]
    @Query private var inboxTasks: [TodoTask]

    private let onClose: (() -> Void)?

    init(workspaceID: UUID?, today: Date, onClose: (() -> Void)?) {
        let dayAfterTomorrow = Calendar.current.date(byAdding: .day, value: 2, to: today) ?? today
        _starting = Query(filter: TodoTask.openStartingPredicate(
            from: today, to: dayAfterTomorrow, workspaceID: workspaceID
        ))
        _due = Query(filter: TodoTask.openDuePredicate(before: dayAfterTomorrow, workspaceID: workspaceID))
        _inboxTasks = Query(filter: TodoTask.inboxPredicate(workspaceID: workspaceID))
        self.onClose = onClose
    }

    /// Oggi e domani (inizio) + scadenze fino a domani, scadute comprese.
    private var openTasks: [TodoTask] {
        TodoTask.mergingUnique([starting, due]).filter { !$0.isTemplate && !$0.isPhase }
    }

    private var inboxCount: Int { inboxTasks.count }

    private var calendar: Calendar { .current }

    private var todayEvents: [TodoTask] {
        openTasks
            .filter {
                ($0.kind == .event || $0.kind == .shootDay)
                    && $0.startAt.map { calendar.isDateInToday($0) } == true
            }
            .sorted { ($0.startAt ?? .now) < ($1.startAt ?? .now) }
    }

    private var dueToday: [TodoTask] {
        let endOfToday = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)
        ) ?? .now
        return openTasks
            .filter { task in
                guard task.kind != .event, task.kind != .shootDay,
                      let dueAt = task.dueAt else { return false }
                return dueAt < endOfToday
            }
            .sorted { ($0.dueAt ?? .now, $1.priorityRaw)
                    < ($1.dueAt ?? .now, $0.priorityRaw) }
    }

    private var tomorrowEvents: Int {
        openTasks.filter {
            ($0.kind == .event || $0.kind == .shootDay)
                && $0.startAt.map { calendar.isDateInTomorrow($0) } == true
        }.count
    }

    private var tomorrowDeadlines: Int {
        openTasks.filter {
            $0.dueAt.map { calendar.isDateInTomorrow($0) } == true
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.xl) {
                header

                panelSection("Agenda", systemImage: "calendar",
                             tint: AppSection.calendar.tint) {
                    if todayEvents.isEmpty {
                        emptyLine("Nessun evento oggi")
                    } else {
                        ForEach(todayEvents, id: \.id) { event in
                            eventRow(event)
                        }
                    }
                }

                panelSection("Scadenze", systemImage: "flag",
                             tint: AppSection.dashboard.tint) {
                    if dueToday.isEmpty {
                        emptyLine("Niente in scadenza")
                    } else {
                        ForEach(dueToday.prefix(8), id: \.id) { task in
                            deadlineRow(task)
                        }
                    }
                }

                inboxCard
                tomorrowCard
            }
            .padding(DS.l)
        }
        .frame(minWidth: 250)
    }

    // MARK: Testata

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Oggi")
                    .font(.dsSectionTitle)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chiudi pannello Oggi")
            }
        }
    }

    // MARK: Sezioni

    private func panelSection<Content: View>(
        _ title: String, systemImage: String, tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.s) {
            Label {
                Text(title.uppercased())
                    .font(.dsCaption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: systemImage)
                    .font(.dsCaption)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: DS.xs) {
                content()
            }
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.dsCaption)
            .foregroundStyle(.tertiary)
            .padding(.vertical, DS.xs)
    }

    private func eventRow(_ event: TodoTask) -> some View {
        Button {
            router.open(taskID: event.id)
        } label: {
            HStack(spacing: DS.s) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(event.project.map { Color(hex: $0.colorHex) }
                          ?? AppSection.calendar.tint)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.dsMeta.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let startAt = event.startAt {
                        Text(event.allDay
                             ? "Tutto il giorno"
                             : "\(startAt.dsTimeLabel)\(event.endAt.map { "–\($0.dsTimeLabel)" } ?? "")")
                            .font(.dsCaption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if event.kind == .shootDay {
                    Image(systemName: "movieclapper")
                        .font(.dsCaption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deadlineRow(_ task: TodoTask) -> some View {
        HStack(spacing: DS.s) {
            Button {
                withAnimation(.dsSoft) { task.toggleDone() }
            } label: {
                Image(systemName: "circle")
                    .font(.dsMeta)
                    .foregroundStyle(task.isOverdue ? DSColor.overdue : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Completa \(task.title)")
            Button {
                router.open(taskID: task.id)
            } label: {
                HStack(spacing: DS.xs) {
                    Text(task.title)
                        .font(.dsMeta)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if task.isOverdue {
                        Text("ritardo")
                            .font(.dsCaption)
                            .foregroundStyle(DSColor.overdue)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: Card

    private var inboxCard: some View {
        Button {
            router.go(.inbox)
        } label: {
            HStack(spacing: DS.s) {
                Image(systemName: "tray.fill")
                    .foregroundStyle(AppSection.inbox.tint)
                Text("Inbox")
                    .font(.dsMeta.weight(.medium))
                Spacer()
                Text("\(inboxCount)")
                    .font(.dsNumeric)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.right")
                    .font(.dsCaption)
                    .foregroundStyle(.tertiary)
            }
            .padding(DS.m)
            .background(DSColor.surfaceSecondary,
                        in: RoundedRectangle(cornerRadius: DS.Radius.medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tomorrowCard: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            Text("DOMANI")
                .font(.dsCaption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: DS.l) {
                Label("\(tomorrowEvents) eventi", systemImage: "calendar")
                Label("\(tomorrowDeadlines) scadenze", systemImage: "flag")
            }
            .font(.dsCaption)
            .foregroundStyle(.secondary)
        }
        .padding(DS.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surfaceSecondary,
                    in: RoundedRectangle(cornerRadius: DS.Radius.medium))
    }
}

#Preview {
    TodayPanelView()
        .environment(AppRouter())
        .modelContainer(PreviewSampleData.make().container)
        .frame(width: 320, height: 700)
}
