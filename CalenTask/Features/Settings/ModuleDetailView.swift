import Foundation
import SwiftUI
import SwiftData

/// La pagina di UN modulo (richiesta di Ivan, 2026-09-10: i moduli sono
/// "quasi app personalizzabili nelle funzioni al loro interno"): testata con
/// interruttore, funzioni interne con la loro spiegazione, poi le
/// preferenze proprie del modulo (`ModuleOptions`). Come le pagine per-app
/// di Impostazioni di iOS.
struct ModuleDetailView: View {
    let module: AppModule

    @Environment(SettingsRouter.self) private var router
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""

    private var configuration: AppConfiguration { .decode(configurationRaw) }
    private var isEnabled: Bool { configuration.isEnabled(module) }
    private var needsProjects: Bool { module == .production && !configuration.isEnabled(.projects) }
    private var features: [AppFeature] { AppFeature.moduleFeatures(of: module) }

    var body: some View {
        Form {
            Section {
                SettingsPageHeader(page: .module(module)) { headerAccessory }
            }

            if needsProjects {
                Section {
                    SettingsLinkRow(
                        title: "Richiede Progetti",
                        detail: "Produzione lavora dentro i progetti: attiva prima il modulo Progetti.",
                        systemImage: AppModule.projects.icon, tint: AppModule.projects.tint
                    ) { router.open(.module(.projects)) }
                }
            }

            if !features.isEmpty {
                Section {
                    ForEach(features) { feature in
                        SettingsToggleRow(
                            title: feature.title, detail: feature.detail,
                            systemImage: feature.icon, tint: module.tint,
                            isOn: featureBinding(feature)
                        )
                        .accessibilityIdentifier("feature.\(feature.rawValue)")
                    }
                } header: {
                    Text("Funzioni")
                } footer: {
                    if !isEnabled {
                        Text("Attiva \(module.title) per usare queste funzioni.")
                    }
                }
                .disabled(!isEnabled)
            }

            if isEnabled {
                ModuleOptions(module: module, configuration: configuration)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(module.title)
    }

    @ViewBuilder
    private var headerAccessory: some View {
        if module == .calendar {
            Text("Sempre attivo")
                .font(.dsCaption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.s)
                .padding(.vertical, DS.xs)
                .background(.quaternary, in: Capsule())
        } else {
            Toggle("Attiva \(module.title)",
                   isOn: AppConfiguration.binding(for: module, in: $configurationRaw))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(needsProjects)
                .accessibilityIdentifier("module.\(module.rawValue)")
        }
    }

    private func featureBinding(_ feature: AppFeature) -> Binding<Bool> {
        let binding = AppConfiguration.binding(for: feature, in: $configurationRaw)
        guard feature == .calendarWeather else { return binding }
        // Un solo interruttore per il meteo: accenderlo riaccende anche la
        // preferenza del calendario (che prima aveva un suo toggle doppione).
        return Binding(get: { binding.wrappedValue }, set: { value in
            binding.wrappedValue = value
            if value { UserDefaults.standard.set(true, forKey: "weatherEnabled") }
        })
    }
}

#Preview {
    NavigationStack {
        ModuleDetailView(module: .calendar)
    }
    .environment(SettingsRouter())
    .modelContainer(PreviewSampleData.make().container)
}
