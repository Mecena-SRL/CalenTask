import SwiftUI

/// Riga condivisa di un modulo: icona, titolo, stato — nella barra laterale
/// (Mac), nell'elenco (iPhone) e nella panoramica.
struct ModuleRowLabel: View {
    let module: AppModule
    let configuration: AppConfiguration

    private var statusLine: String {
        if module == .calendar { return "Sempre attivo" }
        guard configuration.isEnabled(module) else {
            return module == .production && !configuration.isEnabled(.projects)
                ? "Richiede Progetti" : "Disattivato"
        }
        let features = AppFeature.moduleFeatures(of: module)
        let active = features.filter { configuration.isEnabled($0) }.count
        return features.isEmpty ? "Attivo" : "Attivo · \(active) di \(features.count) funzioni"
    }

    var body: some View {
        HStack(spacing: DS.m) {
            DSIconTile(systemImage: module.icon, tint: module.tint)
                .opacity(configuration.isEnabled(module) ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.title)
                    .font(.dsMeta.weight(.medium))
                Text(statusLine)
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Mutation condivisa: riordina i moduli spostabili (Calendario resta
/// primo, "sempre attivo") e ripubblica la configurazione.
func moveModules(
    from source: IndexSet, to destination: Int,
    configurationRaw: inout String
) {
    var configuration = AppConfiguration.decode(configurationRaw)
    var reorderable = configuration.moduleOrder.filter { $0 != .calendar }
    reorderable.move(fromOffsets: source, toOffset: destination)
    configuration.moduleOrder = reorderable
    configurationRaw = configuration.encoded()
}

/// Panoramica dei moduli: accendi/spegni tutto da qui, apri la pagina di un
/// modulo, riordina, torna alla configurazione essenziale.
struct ModulesOverviewView: View {
    @Environment(SettingsRouter.self) private var router
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    @State private var confirmsReset = false

    private var configuration: AppConfiguration { .decode(configurationRaw) }

    private var reorderableModules: [AppModule] {
        configuration.moduleOrder.filter { $0 != .calendar }
    }

    var body: some View {
        Form {
            Section { SettingsPageHeader(page: .modules) }

            Section {
                moduleRow(.calendar)
                ForEach(reorderableModules) { module in
                    moduleRow(module)
                }
                .onMove { source, destination in
                    moveModules(from: source, to: destination, configurationRaw: &configurationRaw)
                }
            } header: {
                Text("Moduli")
            } footer: {
                #if os(macOS)
                Text("Trascina i moduli nella barra laterale per riordinarli: lo stesso ordine vale nell'app.")
                #else
                Text("Tocca Modifica per riordinare: lo stesso ordine vale nell'app.")
                #endif
            }

            Section {
                Button("Ripristina configurazione essenziale", role: .destructive) {
                    confirmsReset = true
                }
            } footer: {
                Text("Torna a Calendario e Attività. Dati e preferenze dei singoli moduli restano dove sono.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPage.modules.title)
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
        .confirmationDialog("Ripristinare la configurazione essenziale?",
                            isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Ripristina", role: .destructive) {
                configurationRaw = AppConfiguration.standard.encoded()
            }
        }
    }

    private func moduleRow(_ module: AppModule) -> some View {
        HStack(spacing: DS.m) {
            Button {
                router.open(.module(module))
            } label: {
                HStack {
                    ModuleRowLabel(module: module, configuration: configuration)
                    Spacer(minLength: DS.s)
                    Image(systemName: "chevron.right")
                        .font(.dsCaption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if module == .calendar {
                Text("Sempre attivo")
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Attiva \(module.title)",
                       isOn: AppConfiguration.binding(for: module, in: $configurationRaw))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(module == .production && !configuration.isEnabled(.projects))
                    .accessibilityIdentifier("module.\(module.rawValue)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        ModulesOverviewView()
    }
    .environment(SettingsRouter())
}
