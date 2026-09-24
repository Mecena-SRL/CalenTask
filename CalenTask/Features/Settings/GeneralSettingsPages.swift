import Foundation
import SwiftUI
import SwiftData
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

// Le pagine "Generali": come si comporta CalenTask, indipendentemente dai
// moduli accesi.

// MARK: Generale

struct GeneralSettingsView: View {
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    @AppStorage("didShowWelcome") private var didShowWelcome = false
    @AppStorage("inboxHintDismissed") private var inboxHintDismissed = false
    @State private var guidesReset = false

    private var configuration: AppConfiguration { .decode(configurationRaw) }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section { SettingsPageHeader(page: .general) }

            Section {
                Picker(selection: AppConfiguration.startPageBinding(in: $configurationRaw)) {
                    ForEach(AppStartPage.allCases.filter {
                        $0 != .quick || configuration.isEnabled(.activities)
                    }) { page in
                        Text(page.title).tag(page)
                    }
                } label: {
                    DSFieldRow(label: "Schermata iniziale", systemImage: "arrow.up.forward.app",
                               tint: .blue, value: "La prima cosa che vedi quando apri CalenTask.") { EmptyView() }
                }
            } header: {
                Text("Avvio")
            }

            Section {
                SettingsToggleRow(
                    title: AppFeature.todayInspector.title, detail: AppFeature.todayInspector.detail,
                    systemImage: AppFeature.todayInspector.icon, tint: AppModule.calendar.tint,
                    isOn: AppConfiguration.binding(for: .todayInspector, in: $configurationRaw)
                )
            } header: {
                Text("Finestra")
            }

            Section {
                Button {
                    didShowWelcome = false
                    inboxHintDismissed = false
                    withAnimation(.dsQuick) { guidesReset = true }
                } label: {
                    DSFieldRow(label: "Mostra di nuovo guide e suggerimenti",
                               systemImage: "lightbulb", tint: .yellow,
                               value: "Il benvenuto e i suggerimenti ricompaiono al prossimo avvio.") {
                        if guidesReset {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("Guide")
            }

            Section {
                LabeledContent("Versione", value: appVersion)
            } header: {
                Text("Informazioni")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPage.general.title)
    }
}

// MARK: Aspetto (D47)

struct AppearanceSettingsView: View {
    @AppStorage(DSAppearance.storageKey) private var appearanceRaw = DSAppearance.auto.rawValue
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    @AppStorage("sidebarShowsFavorites") private var showsFavorites = true
    @AppStorage("sidebarShowsProjects") private var showsProjects = true
    @AppStorage("sidebarShowsLists") private var showsLists = true
    @AppStorage("sidebarShowsTags") private var showsTags = true

    private var configuration: AppConfiguration { .decode(configurationRaw) }

    var body: some View {
        Form {
            Section { SettingsPageHeader(page: .appearance) }

            Section {
                HStack(spacing: DS.m) {
                    ForEach(DSAppearance.available) { appearance in
                        appearanceCard(appearance)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.xs)
            } header: {
                Text("Tema")
            } footer: {
                #if os(macOS)
                Text("Misto: barra laterale scura, contenuto chiaro o secondo il sistema.")
                #endif
            }

            Section {
                if configuration.isEnabled(.projects) {
                    SettingsToggleRow(title: "Preferiti", detail: "I progetti con la stella, in cima.",
                                      systemImage: "star", tint: .yellow, isOn: $showsFavorites)
                    SettingsToggleRow(title: "Progetti", detail: "L'elenco dei progetti dello spazio attivo.",
                                      systemImage: AppModule.projects.icon, tint: AppModule.projects.tint,
                                      isOn: $showsProjects)
                }
                if configuration.isEnabled(.smartLists) {
                    SettingsToggleRow(title: "Liste smart", detail: "Le viste salvate con i loro filtri.",
                                      systemImage: AppFeature.smartLists.icon, tint: AppModule.activities.tint,
                                      isOn: $showsLists)
                }
                if configuration.isEnabled(.tags) {
                    SettingsToggleRow(title: "Etichette", detail: "Le etichette con il numero di attività aperte.",
                                      systemImage: AppFeature.tags.icon, tint: .indigo, isOn: $showsTags)
                }
                SettingsToggleRow(
                    title: AppFeature.sidebarMiniCalendar.title, detail: AppFeature.sidebarMiniCalendar.detail,
                    systemImage: AppFeature.sidebarMiniCalendar.icon, tint: AppModule.calendar.tint,
                    isOn: AppConfiguration.binding(for: .sidebarMiniCalendar, in: $configurationRaw)
                )
            } header: {
                Text("Barra laterale")
            } footer: {
                Text("Su Mac e iPad. Le sezioni dei moduli spenti non compaiono.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPage.appearance.title)
    }

    private func appearanceCard(_ appearance: DSAppearance) -> some View {
        let isSelected = appearanceRaw == appearance.rawValue
        return Button {
            withAnimation(.dsQuick) { appearanceRaw = appearance.rawValue }
        } label: {
            VStack(spacing: DS.s) {
                Image(systemName: appearance.systemImage)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(DSColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: DS.Radius.medium))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.medium)
                            .strokeBorder(isSelected ? Color.accentColor : DSColor.hairline,
                                          lineWidth: isSelected ? 2 : 1)
                    }
                Text(appearance.label)
                    .font(.dsCaption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Notifiche

struct NotificationsSettingsView: View {
    @AppStorage(NotificationService.digestEnabledKey) private var digestEnabled = true
    @Environment(\.openURL) private var openURL
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        Form {
            Section { SettingsPageHeader(page: .notifications) }

            Section {
                DSFieldRow(label: statusTitle, systemImage: statusIcon, tint: statusTint, value: statusDetail) {
                    if status == .notDetermined {
                        Button("Consenti") {
                            Task {
                                await NotificationService.shared.requestAuthorizationIfNeeded()
                                await refreshStatus()
                            }
                        }
                    } else if status == .denied {
                        Button("Apri Impostazioni") { openSystemSettings() }
                    }
                }
            } header: {
                Text("Permesso")
            }

            Section {
                SettingsToggleRow(
                    title: "Digest giornaliero",
                    detail: "Una notifica silenziosa alle 8:00 con eventi, scadenze e arretrati del giorno.",
                    systemImage: "sunrise", tint: .orange, isOn: $digestEnabled
                )
            } header: {
                Text("Riepilogo")
            } footer: {
                Text("Promemoria, scadenze e anticipi degli eventi si impostano su ogni attività.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPage.notifications.title)
        .task { await refreshStatus() }
    }

    private var isAllowed: Bool { status == .authorized || status == .provisional }

    private var statusTitle: String {
        switch status {
        case .none: "Verifica in corso…"
        case .some(.denied): "Notifiche bloccate"
        case .some(.notDetermined): "Permesso non ancora chiesto"
        default: "Notifiche consentite"
        }
    }

    private var statusDetail: String {
        switch status {
        case .none: ""
        case .some(.denied): "Consentile nelle impostazioni di sistema per ricevere promemoria e scadenze."
        case .some(.notDetermined): "CalenTask lo chiede la prima volta che serve un avviso."
        default: "Promemoria, scadenze e avvisi degli eventi arrivano anche ad app chiusa."
        }
    }

    private var statusIcon: String {
        status == .denied ? "bell.slash.fill" : isAllowed ? "bell.badge.fill" : "bell"
    }

    private var statusTint: Color {
        status == .denied ? .red : isAllowed ? .green : .gray
    }

    private func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func openSystemSettings() {
        #if os(macOS)
        let target = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        #else
        let target = UIApplication.openNotificationSettingsURLString
        #endif
        if let url = URL(string: target) { openURL(url) }
    }
}

// MARK: Sincronizzazione

struct SyncSettingsView: View {
    @AppStorage(CalendarSyncService.syncEnabledKey) private var calendarSyncEnabled = false
    @State private var calendarSync = CalendarSyncService.shared

    var body: some View {
        Form {
            Section { SettingsPageHeader(page: .sync) }

            Section {
                ICloudStatusRow()
            } header: {
                Text("iCloud")
            } footer: {
                Text("Attività, progetti, contatti e spazi viaggiano con iCloud. Le preferenze di Impostazioni restano su ogni dispositivo.")
            }

            Section {
                SettingsToggleRow(
                    title: "Calendari di sistema",
                    detail: "Importa ed esporta gli eventi di Calendario, compresi gli account Google ed Exchange del dispositivo.",
                    systemImage: "calendar.badge.clock", tint: AppModule.calendar.tint,
                    isOn: $calendarSyncEnabled
                )
                if calendarSyncEnabled && !calendarSync.isAuthorized {
                    Button("Consenti l'accesso ai calendari") {
                        Task { await calendarSync.requestAccessIfNeeded() }
                    }
                }
                if let lastSyncAt = calendarSync.lastSyncAt {
                    LabeledContent("Ultima sincronizzazione",
                                   value: lastSyncAt.formatted(.relative(presentation: .named)))
                }
                if let lastError = calendarSync.lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .font(.dsCaption)
                        .foregroundStyle(DSColor.overdue)
                }
            } header: {
                Text("Calendari")
            } footer: {
                Text("Senza tasto \"sincronizza\": all'apertura del Calendario e a ogni modifica di un evento. Ogni dispositivo sincronizza i propri calendari.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPage.sync.title)
    }
}

// MARK: Account e spazi

struct AccountSettingsView: View {
    var body: some View {
        Form {
            Section { SettingsPageHeader(page: .account) }
            AccountSection()
            WorkspacesSettingsSection()
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPage.account.title)
    }
}
