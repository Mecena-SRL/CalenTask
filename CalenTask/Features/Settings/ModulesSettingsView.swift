import SwiftUI

/// Riga condivisa di un modulo: icona, titolo, stato — usata sia dalla
/// barra laterale macOS (in `SettingsView`) sia dall'elenco iOS qui sotto.
struct ModuleRowLabel: View {
    let module: AppModule
    let configuration: AppConfiguration

    private var statusLine: String {
        if module == .calendar { return "Sempre attivo" }
        guard configuration.isEnabled(module) else { return "Disattivato" }
        let active = AppFeature.allCases.filter { $0.module == module && configuration.isEnabled($0) }.count
        let total = AppFeature.allCases.filter { $0.module == module }.count
        return total > 0 ? "Attivo · \(active) di \(total) funzioni" : "Attivo"
    }

    var body: some View {
        HStack(spacing: DS.m) {
            DSIconTile(systemImage: module.icon, tint: module.tint)
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

/// Mutation condivisa (anche da `SettingsView` su Mac): riordina i moduli
/// spostabili (Calendario resta primo, "sempre attivo" — non ha senso
/// spostarlo) e ripubblica la configurazione.
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

/// iPhone / iPad compatto: elenco a scorrimento con push verso
/// `ModuleDetailView` (comportamento nativo di `NavigationStack`).
struct ModulesSettingsView: View {
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    private var configuration: AppConfiguration { .decode(configurationRaw) }

    private var reorderableModules: [AppModule] {
        configuration.moduleOrder.filter { $0 != .calendar }
    }

    var body: some View {
        Form {
            Section {
                Picker("All'avvio", selection: startPageBinding) {
                    ForEach(AppStartPage.allCases.filter {
                        $0 != .quick || configuration.isEnabled(.activities)
                    }) { page in
                        Text(page.title).tag(page)
                    }
                }
            } header: {
                Text("La tua app")
            } footer: {
                Text("Parti dal calendario e aggiungi ciò che ti serve.")
            }

            Section {
                NavigationLink { ModuleDetailView(module: .calendar) } label: {
                    ModuleRowLabel(module: .calendar, configuration: configuration)
                }
                ForEach(reorderableModules) { module in
                    NavigationLink { ModuleDetailView(module: module) } label: {
                        ModuleRowLabel(module: module, configuration: configuration)
                    }
                }
                .onMove { source, destination in
                    moveModules(from: source, to: destination, configurationRaw: &configurationRaw)
                }
            } footer: {
                Text("Trascina per riordinare: lo stesso ordine vale nella barra laterale dell'app. Disattivare un modulo nasconde i suoi strumenti e conserva tutti i dati e le tue preferenze.")
            }

            Section {
                Button("Ripristina configurazione essenziale") {
                    configurationRaw = AppConfiguration.standard.encoded()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Moduli")
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
    }

    private var startPageBinding: Binding<AppStartPage> {
        Binding(get: {
            configuration.startPage == .quick && !configuration.isEnabled(.activities)
                ? .calendar : configuration.startPage
        }, set: { value in
            var updated = configuration
            updated.startPage = value
            configurationRaw = updated.encoded()
        })
    }
}

#Preview {
    NavigationStack {
        ModulesSettingsView()
    }
}
