import SwiftUI
import SwiftData

/// La pagina profonda di UN modulo (richiesta di Ivan, 2026-09-10: i moduli
/// devono essere "quasi una sorta di app personalizzabili nelle funzioni al
/// loro interno"). Prima le opzioni di Calendario/Rapida/Sync vivevano in
/// tab separate dai moduli che le governano; ora ogni modulo è un posto
/// solo — attivazione, funzioni interne, preferenze — come le pagine per-app
/// di Impostazioni di iOS.
struct ModuleDetailView: View {
    let module: AppModule

    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    private var configuration: AppConfiguration { .decode(configurationRaw) }

    private func moduleBinding(_ module: AppModule) -> Binding<Bool> {
        Binding(get: { configuration.isEnabled(module) }, set: { value in
            var updated = configuration
            updated.set(module, enabled: value)
            configurationRaw = updated.encoded()
        })
    }

    private func featureBinding(_ feature: AppFeature) -> Binding<Bool> {
        Binding(get: { configuration.isEnabled(feature) }, set: { value in
            var updated = configuration
            updated.set(feature, enabled: value)
            configurationRaw = updated.encoded()
        })
    }

    private var features: [AppFeature] {
        AppFeature.allCases.filter { $0.module == module }
    }

    var body: some View {
        Form {
            Section {
                if module == .calendar {
                    Label("Sempre attivo", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("Attiva \(module.title)", isOn: moduleBinding(module))
                        .accessibilityIdentifier("module.\(module.rawValue)")
                        .disabled(module == .production && !configuration.isEnabled(.projects))
                }
            } footer: {
                Text(module.detail)
            }

            if configuration.isEnabled(module) {
                if !features.isEmpty {
                    Section("Funzioni") {
                        ForEach(features) { feature in
                            Toggle(feature.title, isOn: featureBinding(feature))
                                .accessibilityIdentifier("feature.\(feature.rawValue)")
                        }
                    }
                }

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
        .formStyle(.grouped)
        .navigationTitle(module.title)
    }
}

// MARK: Calendario

private struct CalendarModuleOptions: View {
    let configuration: AppConfiguration

    @AppStorage("calendarViewMode") private var calendarModeRaw = CalendarViewMode.month.rawValue
    @AppStorage("calendarDayMode") private var dayModeRaw = "agenda"
    @AppStorage("weatherEnabled") private var weatherEnabled = true
    @State private var calendarSync = CalendarSyncService.shared

    var body: some View {
        viewsSection
        weatherSection
        syncSection
    }

    private var viewsSection: some View {
        Section("Viste") {
            Picker(selection: Binding(get: {
                let mode = CalendarViewMode(rawValue: calendarModeRaw) ?? .month
                return configuration.isEnabled(.calendarAdvancedViews) || [.day, .week, .month].contains(mode)
                    ? mode.rawValue : CalendarViewMode.month.rawValue
            }, set: { calendarModeRaw = $0 })) {
                ForEach(CalendarViewMode.allCases.filter {
                    configuration.isEnabled(.calendarAdvancedViews) || [.day, .week, .month].contains($0)
                }) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            } label: {
                DSFieldRow(label: "Vista predefinita", systemImage: "calendar",
                           tint: .red) { EmptyView() }
            }
            Picker(selection: $dayModeRaw) {
                Text("Agenda").tag("agenda")
                Text("Griglia oraria").tag("grid")
            } label: {
                DSFieldRow(label: "Dettaglio giorno", systemImage: "calendar.day.timeline.left",
                           tint: .blue) { EmptyView() }
            }
        }
    }

    @ViewBuilder
    private var weatherSection: some View {
        if configuration.isEnabled(.calendarWeather) {
            Section {
                Toggle(isOn: $weatherEnabled) {
                    DSFieldRow(label: "Meteo nel calendario", systemImage: "cloud.sun",
                               tint: .cyan) { EmptyView() }
                }
            } footer: {
                Text("Previsioni nelle viste giorno e settimana e sulle attività dei prossimi giorni — utili per pianificare le riprese in esterni. Posizione usata solo per il meteo.")
                    .font(.dsCaption)
            }
        }
    }

    private var syncSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { calendarSync.isSyncEnabled },
                set: { calendarSync.isSyncEnabled = $0 }
            )) {
                DSFieldRow(label: "Sincronizzazione eventi",
                           systemImage: "arrow.triangle.2.circlepath",
                           tint: .green) { EmptyView() }
            }
            if let lastSyncAt = calendarSync.lastSyncAt {
                LabeledContent("Ultima sincronizzazione",
                               value: lastSyncAt.formatted(.dateTime.hour().minute()))
                    .font(.dsCaption)
            }
            if let lastError = calendarSync.lastError {
                Text("Errore: \(lastError)")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.overdue)
            }
        } header: {
            Text("Calendari di sistema (Apple e Google)")
        } footer: {
            Text("Importa ed esporta in automatico, senza bisogno di un tasto \"sincronizza\": all'apertura del Calendario e a ogni modifica di un'attività.")
                .font(.dsCaption)
        }
    }
}

// MARK: Attività

private struct ActivitiesModuleOptions: View {
    let configuration: AppConfiguration

    @AppStorage("quickShowsDue") private var showsDue = true
    @AppStorage("quickShowsPhase") private var showsPhase = true
    @AppStorage("quickShowsPriority") private var showsPriority = false
    @AppStorage("quickShowsNotes") private var showsNotes = false
    @State private var showsTags = false

    var body: some View {
        quickFieldsSection
        digestSection
        tagsSection
    }

    private var quickFieldsSection: some View {
        Section("Campi visibili nelle card Rapida") {
            Toggle(isOn: $showsDue) {
                DSFieldRow(label: "Scadenza", systemImage: "flag", tint: .orange) { EmptyView() }
            }
            Toggle(isOn: $showsPhase) {
                DSFieldRow(label: "Fase e colore", systemImage: "square.stack.3d.up",
                           tint: .purple) { EmptyView() }
            }
            Toggle(isOn: $showsPriority) {
                DSFieldRow(label: "Priorità", systemImage: "flag.circle", tint: .red) { EmptyView() }
            }
            Toggle(isOn: $showsNotes) {
                DSFieldRow(label: "Anteprima note", systemImage: "note.text", tint: .gray) { EmptyView() }
            }
        }
    }

    private var digestSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: {
                    UserDefaults.standard.object(
                        forKey: NotificationService.digestEnabledKey) as? Bool ?? true
                },
                set: { UserDefaults.standard.set($0, forKey: NotificationService.digestEnabledKey) }
            )) {
                DSFieldRow(label: "Digest giornaliero", systemImage: "sunrise",
                           tint: .orange) { EmptyView() }
            }
        } footer: {
            Text("Una sola notifica silenziosa alle 8:00 con eventi, scadenze e arretrati del giorno.")
                .font(.dsCaption)
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if configuration.isEnabled(.tags) {
            Section {
                Button {
                    showsTags = true
                } label: {
                    DSFieldRow(label: "Etichette…", systemImage: "number", tint: .indigo) {
                        Image(systemName: "chevron.right")
                            .font(.dsCaption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showsTags) { TagManagerView() }
            }
        }
    }
}

// MARK: Progetti

private struct ProjectsModuleOptions: View {
    var body: some View {
        Section {
            Text("Progetti, fasi e pianificazione a lotti. Le preferenze per-progetto (vista, colore, campi) si scelgono aprendo un progetto.")
                .font(.dsCaption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: Persone

private struct PeopleModuleOptions: View {
    let configuration: AppConfiguration

    @AppStorage("dashboardRole") private var roleRaw = DashboardRole.full.rawValue
    @State private var showsTeam = false

    var body: some View {
        teamSection
        dashboardSection
    }

    private var teamSection: some View {
        Section {
            Button {
                showsTeam = true
            } label: {
                DSFieldRow(label: "Team…", systemImage: "person.2", tint: .teal) {
                    Image(systemName: "chevron.right")
                        .font(.dsCaption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showsTeam) { TeamView() }
        }
    }

    @ViewBuilder
    private var dashboardSection: some View {
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
                Text("Dashboard")
            } footer: {
                Text("Ogni persona vede il proprio cruscotto invece della Home completa.")
                    .font(.dsCaption)
            }
        }
    }
}

// MARK: Produzione

private struct ProductionModuleOptions: View {
    @State private var showsCrew = false

    var body: some View {
        Section {
            Button {
                showsCrew = true
            } label: {
                DSFieldRow(label: "Troupe e risorse…", systemImage: "movieclapper",
                           tint: .orange) {
                    Image(systemName: "chevron.right")
                        .font(.dsCaption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showsCrew) { CrewView() }
        }
    }
}

#Preview {
    NavigationStack {
        ModuleDetailView(module: .calendar)
    }
    .modelContainer(PreviewSampleData.make().container)
}
