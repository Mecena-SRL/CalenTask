import Foundation
import SwiftUI

/// Le preferenze proprie di ogni modulo, sotto le sue "Funzioni".
/// Nuovo modulo → nuovo `case` qui (e le sue voci in `SettingsSearch`).
struct ModuleOptions: View {
    let module: AppModule
    let configuration: AppConfiguration

    var body: some View {
        switch module {
        case .calendar: CalendarModuleOptions(configuration: configuration)
        case .activities: ActivitiesModuleOptions(configuration: configuration)
        case .projects: ProjectsModuleOptions()
        case .people: PeopleModuleOptions(configuration: configuration)
        case .insights: EmptyView()
        case .production: ProductionModuleOptions()
        }
    }
}

// MARK: Calendario

private struct CalendarModuleOptions: View {
    let configuration: AppConfiguration

    @Environment(SettingsRouter.self) private var router
    @AppStorage("calendarViewMode") private var calendarModeRaw = CalendarViewMode.month.rawValue
    @AppStorage("calendarDayMode") private var dayModeRaw = "agenda"
    @AppStorage("calendarWeekDayCount") private var weekDayCount = 7
    @AppStorage("calendarShowsQuarter") private var showsQuarter = true
    @AppStorage("calendarMonthHeatmap") private var monthHeatmap = false
    @AppStorage(CalendarWorkHours.startKey) private var workStart = CalendarWorkHours.defaultStart
    @AppStorage(CalendarWorkHours.endKey) private var workEnd = CalendarWorkHours.defaultEnd

    private var advancedViews: Bool { configuration.isEnabled(.calendarAdvancedViews) }

    private var availableModes: [CalendarViewMode] {
        CalendarViewMode.allCases.filter { advancedViews || [.day, .week, .month].contains($0) }
    }

    var body: some View {
        Section {
            Picker(selection: Binding(get: {
                let mode = CalendarViewMode(rawValue: calendarModeRaw) ?? .month
                return availableModes.contains(mode) ? mode.rawValue : CalendarViewMode.month.rawValue
            }, set: { calendarModeRaw = $0 })) {
                ForEach(availableModes) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            } label: {
                DSFieldRow(label: "Vista predefinita", systemImage: "calendar", tint: .red) { EmptyView() }
            }
            Picker(selection: $dayModeRaw) {
                Text("Agenda").tag("agenda")
                Text("Griglia oraria").tag("grid")
            } label: {
                DSFieldRow(label: "Dettaglio giorno", systemImage: "calendar.day.timeline.left",
                           tint: .blue) { EmptyView() }
            }
            if advancedViews {
                Picker(selection: $weekDayCount) {
                    ForEach([2, 3, 5, 7, 9], id: \.self) { count in
                        Text(count == 7 ? "Settimana intera" : "\(count) giorni").tag(count)
                    }
                } label: {
                    DSFieldRow(label: "Giorni della vista settimana", systemImage: "calendar.day.timeline.leading",
                               tint: .indigo) { EmptyView() }
                }
                SettingsToggleRow(title: "Trimestre", detail: "La vista per pianificare a lungo termine (anche le tasse).",
                                  systemImage: "calendar.badge.clock", tint: .purple, isOn: $showsQuarter)
            }
            SettingsToggleRow(title: "Mappa di calore del mese",
                              detail: "Colora i giorni in base a quanto sono pieni. In Anno è sempre attiva.",
                              systemImage: "square.grid.3x3.fill", tint: .orange, isOn: $monthHeatmap)
        } header: {
            Text("Viste")
        }

        Section {
            Picker(selection: Binding(get: { workStart }, set: { value in
                workStart = value
                if workEnd <= value { workEnd = min(value + 1, 24) }
            })) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(CalendarGridMetrics.clockLabel(hour * 60)).tag(hour)
                }
            } label: {
                DSFieldRow(label: "Inizio", systemImage: "sunrise", tint: .orange) { EmptyView() }
            }
            Picker(selection: Binding(get: { workEnd }, set: { value in
                workEnd = value
                if workStart >= value { workStart = max(value - 1, 0) }
            })) {
                ForEach(1...24, id: \.self) { hour in
                    Text(CalendarGridMetrics.clockLabel(hour * 60)).tag(hour)
                }
            } label: {
                DSFieldRow(label: "Fine", systemImage: "sunset", tint: .indigo) { EmptyView() }
            }
        } header: {
            Text("Orario di lavoro")
        } footer: {
            Text("Nelle griglie di Giorno e Settimana le ore fuori orario sono più tenui, e la giornata si apre dall'inizio del lavoro (o dall'ora attuale, se è oggi).")
        }

        Section {
            SettingsLinkRow(title: "Calendari di sistema",
                            detail: "Sincronizzazione con Calendario, Google ed Exchange.",
                            systemImage: SettingsPage.sync.systemImage, tint: SettingsPage.sync.tint) {
                router.open(.sync)
            }
        } header: {
            Text("Collegamenti")
        }
    }
}

// MARK: Attività

private struct ActivitiesModuleOptions: View {
    let configuration: AppConfiguration

    @Environment(SettingsRouter.self) private var router
    @AppStorage("quickShowsDue") private var showsDue = true
    @AppStorage("quickShowsPhase") private var showsPhase = true
    @AppStorage("quickShowsPriority") private var showsPriority = false
    @AppStorage("quickShowsNotes") private var showsNotes = false
    @State private var showsTags = false

    var body: some View {
        Section {
            SettingsToggleRow(title: "Scadenza", systemImage: "flag", tint: .orange, isOn: $showsDue)
            SettingsToggleRow(title: "Fase e colore", systemImage: "square.stack.3d.up", tint: .purple,
                              isOn: $showsPhase)
            SettingsToggleRow(title: "Priorità", systemImage: "flag.circle", tint: .red, isOn: $showsPriority)
            SettingsToggleRow(title: "Anteprima note", systemImage: "note.text", tint: .gray, isOn: $showsNotes)
        } header: {
            Text("Campi delle card Rapida")
        }

        Section {
            if configuration.isEnabled(.tags) {
                SettingsLinkRow(title: "Etichette…", detail: "Crea, rinomina e colora le etichette.",
                                systemImage: "number", tint: .indigo) { showsTags = true }
                    .sheet(isPresented: $showsTags) { TagManagerView() }
            }
            SettingsLinkRow(title: "Digest del mattino", detail: "Il riepilogo delle 8:00 è in Notifiche.",
                            systemImage: SettingsPage.notifications.systemImage,
                            tint: SettingsPage.notifications.tint) {
                router.open(.notifications)
            }
        } header: {
            Text("Collegamenti")
        }
    }
}

// MARK: Progetti

private struct ProjectsModuleOptions: View {
    @AppStorage("projectsShowsClosed") private var showsClosed = false
    @AppStorage("ganttComplexRows") private var ganttComplexRows = false

    var body: some View {
        Section {
            SettingsToggleRow(title: "Mostra i progetti chiusi", detail: "Nell'elenco Progetti, insieme a quelli attivi.",
                              systemImage: "archivebox", tint: .gray, isOn: $showsClosed)
            SettingsToggleRow(title: "Gantt dettagliato", detail: "Righe alte con titolo, fase, etichetta e avanzamento.",
                              systemImage: "chart.bar.doc.horizontal", tint: AppModule.projects.tint,
                              isOn: $ganttComplexRows)
        } header: {
            Text("Elenco e Gantt")
        } footer: {
            Text("Vista, colore e campi di ogni progetto si scelgono aprendo il progetto.")
        }
    }
}

// MARK: Persone

private struct PeopleModuleOptions: View {
    let configuration: AppConfiguration

    @AppStorage("dashboardRole") private var roleRaw = DashboardRole.full.rawValue
    @State private var showsTeam = false

    var body: some View {
        Section {
            SettingsLinkRow(title: "Team…", detail: "Persone e carico di lavoro.",
                            systemImage: "person.2", tint: .teal) { showsTeam = true }
                .sheet(isPresented: $showsTeam) { TeamView() }
        }

        if configuration.isEnabled(.activities) {
            Section {
                Picker(selection: $roleRaw) {
                    ForEach(DashboardRole.allCases) { role in
                        Label(role.label, systemImage: role.systemImage).tag(role.rawValue)
                    }
                } label: {
                    DSFieldRow(label: "Vista per ruolo", systemImage: "person.crop.rectangle",
                               tint: .blue) { EmptyView() }
                }
            } header: {
                Text("Oggi")
            } footer: {
                Text("Ogni persona vede il proprio cruscotto invece della Home completa.")
            }
        }
    }
}

// MARK: Produzione

private struct ProductionModuleOptions: View {
    @State private var showsCrew = false

    var body: some View {
        Section {
            SettingsLinkRow(title: "Troupe e risorse…", detail: "Contatti del set, ruoli e attrezzatura.",
                            systemImage: "movieclapper", tint: .orange) { showsCrew = true }
                .sheet(isPresented: $showsCrew) { CrewView() }
        }
    }
}
