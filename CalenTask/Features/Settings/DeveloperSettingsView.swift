import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Impostazioni › Sviluppatore: aggiornamenti dalle release di GitHub
/// (anche pre-release) e le informazioni utili per un report di errore.
struct DeveloperSettingsView: View {
    @AppStorage(UpdateService.includePrereleasesKey) private var includePrereleases = false
    @State private var updates = UpdateService.shared
    @State private var tokenDraft = ""
    /// Solo un segno nelle preferenze: il Portachiavi si legge al controllo
    /// (con la firma ad-hoc ogni build nuova chiede di nuovo il permesso).
    @AppStorage(GitHubTokenStore.savedFlagKey) private var hasToken = false
    @State private var copiedDiagnostics = false
    @AppStorage(LaunchGuard.forceSafeModeKey) private var forceSafeMode = false
    @State private var didResetViews = false

    var body: some View {
        Form {
            Section { SettingsPageHeader(page: .developer) }

            #if os(macOS)
            updatesSection
            tokenSection
            #endif

            Section {
                if LaunchGuard.isSafeMode {
                    Label("Questa sessione è in avvio sicuro.", systemImage: "stethoscope")
                        .foregroundStyle(.orange)
                }
                SettingsToggleRow(
                    title: "Avvio sicuro alla prossima apertura",
                    detail: "Finestra ripristinata, senza pannello destro né mini-calendario. Parte da solo se un avvio si interrompe.",
                    systemImage: "stethoscope", tint: .orange,
                    isOn: $forceSafeMode
                )
                Button {
                    resetViews()
                } label: {
                    Label(didResetViews ? "Fatto: vale dal prossimo avvio" : "Ripristina finestra e viste",
                          systemImage: didResetViews ? "checkmark" : "arrow.counterclockwise")
                }
            } header: {
                Text("Avvio")
            }

            Section {
                LabeledContent("Versione", value: "\(UpdateService.currentVersion) (\(UpdateService.currentBuild))")
                LabeledContent("Archivio dati", value: storeDescription)
                LabeledContent("Sistema", value: ProcessInfo.processInfo.operatingSystemVersionString)
                Button {
                    copyDiagnostics()
                } label: {
                    Label(copiedDiagnostics ? "Copiato" : "Copia informazioni di diagnostica",
                          systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text("Diagnostica")
            } footer: {
                Text("Da incollare in una segnalazione insieme al report di arresto (Console › Report di arresto › CalenTask).")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPage.developer.title)
    }

    // MARK: Aggiornamenti

    #if os(macOS)
    private var updatesSection: some View {
        Section {
            SettingsToggleRow(
                title: "Includi le pre-release",
                detail: "Ricevi anche le versioni di prova, prima che diventino ufficiali.",
                systemImage: "flask", tint: .orange,
                isOn: $includePrereleases
            )

            HStack {
                Button {
                    Task { await updates.checkForUpdates(includePrereleases: includePrereleases) }
                } label: {
                    Label("Controlla aggiornamenti", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(updates.isBusy)
                Spacer()
                if let lastCheckAt = updates.lastCheckAt {
                    Text("Ultimo controllo \(lastCheckAt.formatted(.relative(presentation: .named)))")
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                }
            }

            phaseRow
        } header: {
            Text("Aggiornamenti")
        } footer: {
            Text("Le versioni arrivano dalle release di GitHub. L'app scarica il DMG, si sostituisce e si riavvia; se non può (per esempio senza permessi sulla cartella Applicazioni) apre il DMG da trascinare a mano.")
        }
    }

    @ViewBuilder
    private var phaseRow: some View {
        switch updates.phase {
        case .idle:
            EmptyView()
        case .checking:
            ProgressRow(text: "Controllo in corso…")
        case .upToDate:
            Label("CalenTask è aggiornata (\(UpdateService.currentVersion)).", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .available(let update):
            VStack(alignment: .leading, spacing: DS.s) {
                HStack(spacing: DS.s) {
                    Label("Disponibile la \(update.version)", systemImage: "arrow.down.circle.fill")
                        .font(.dsMeta.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    if update.isPrerelease {
                        Text("pre-release")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Link("Note", destination: update.pageURL)
                        .font(.dsCaption)
                }
                if !update.notes.isEmpty {
                    Text(update.notes)
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }
                Button {
                    Task { await updates.install(update) }
                } label: {
                    Label("Scarica e installa", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, DS.xs)
        case .downloading(let update):
            ProgressRow(text: "Scarico la \(update.version)…")
        case .installing(let update):
            ProgressRow(text: "Installo la \(update.version): l'app si riavvierà.")
        case .manualInstall(let dmg):
            VStack(alignment: .leading, spacing: DS.xs) {
                Label("DMG scaricato e aperto.", systemImage: "externaldrive.fill")
                Text("Trascina CalenTask in Applicazioni per sostituire questa versione. Il file è in \(dmg.deletingLastPathComponent().lastPathComponent).")
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.dsCaption)
                .foregroundStyle(DSColor.overdue)
        }
    }

    private var tokenSection: some View {
        Section {
            if hasToken {
                HStack {
                    Label("Token salvato nel Portachiavi", systemImage: "key.fill")
                    Spacer()
                    Button("Rimuovi", role: .destructive) {
                        GitHubTokenStore.save(nil)
                    }
                }
            } else {
                HStack {
                    SecureField("github_pat_…", text: $tokenDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Salva") {
                        GitHubTokenStore.save(tokenDraft)
                        tokenDraft = ""
                    }
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } header: {
            Text("Accesso a GitHub")
        } footer: {
            Text("Il repository è privato: serve un token GitHub (fine-grained) con permesso \"Contents: Read-only\" sul solo repository CalenTask. Resta nel Portachiavi di questo Mac.")
        }
    }
    #endif

    // MARK: Diagnostica

    private var storeDescription: String {
        if let failure = StoreMode.localFailure { return "Solo memoria — archivio non apribile: \(failure)" }
        if StoreMode.isCloudKit { return "iCloud" }
        if let failure = StoreMode.cloudKitFailure { return "Locale (iCloud: \(failure))" }
        return "Locale"
    }

    private var diagnostics: String {
        [
            "CalenTask \(UpdateService.currentVersion) (\(UpdateService.currentBuild))",
            "Sistema: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Archivio: \(storeDescription)",
            "Avvio sicuro: \(LaunchGuard.isSafeMode ? "sì" : "no")",
            "Configurazione: \(UserDefaults.standard.string(forKey: AppConfiguration.storageKey) ?? "predefinita")",
        ].joined(separator: "\n")
    }

    /// Dimentica dimensioni della finestra, colonne e scelte di vista
    /// (modalità del calendario, gruppi della barra laterale, pannello Oggi).
    private func resetViews() {
        LaunchGuard.resetWindowState()
        let defaults = UserDefaults.standard
        for key in ["calendarViewMode", "calendarDayMode", TodayPanel.storageKey,
                    "sidebarShowsFavorites", "sidebarShowsProjects", "sidebarShowsLists", "sidebarShowsTags"] {
            defaults.removeObject(forKey: key)
        }
        withAnimation(.dsQuick) { didResetViews = true }
    }

    private func copyDiagnostics() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        #else
        UIPasteboard.general.string = diagnostics
        #endif
        withAnimation(.dsQuick) { copiedDiagnostics = true }
    }
}

/// Riga con rotellina e testo.
private struct ProgressRow: View {
    let text: String

    var body: some View {
        HStack(spacing: DS.s) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.dsCaption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack { DeveloperSettingsView() }
}
