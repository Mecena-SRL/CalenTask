import SwiftUI
import SwiftData

/// Impostazioni (D43, riviste): tutte le personalizzazioni in un posto solo.
/// - In testa chi sei (account e iCloud);
/// - **Generali**: come si comporta l'app;
/// - **Moduli**: panoramica e una pagina per modulo.
/// Con la ricerca in cima. macOS: scena Settings (⌘,), barra laterale +
/// pagina. iOS: sheet dall'ingranaggio, elenco con push.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    @State private var router = SettingsRouter()
    @State private var searchText = ""

    private var configuration: AppConfiguration { .decode(configurationRaw) }

    private var reorderableModules: [AppModule] {
        configuration.moduleOrder.filter { $0 != .calendar }
    }

    private var searchResults: [SettingsSearchResult] {
        SettingsSearch.results(for: searchText)
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: Binding(get: { router.selection }, set: { router.selection = $0 })) {
                if searchText.isEmpty {
                    sidebarSections
                } else {
                    searchSection { result in
                        SettingsPageRow(page: result.page, subtitle: matchesLine(result))
                            .tag(result.page)
                    }
                }
            }
            .searchable(text: $searchText, placement: .sidebar, prompt: "Cerca")
            .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 300)
        } detail: {
            SettingsPageView(page: router.selection ?? .general)
                .id(router.selection)
        }
        // Come Impostazioni di Sistema: la barra laterale non si chiude.
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 780, idealWidth: 860, minHeight: 540, idealHeight: 660)
        .background(FloatingWindowConfigurator())
        .environment(router)
        #else
        NavigationStack(path: Binding(get: { router.path }, set: { router.path = $0 })) {
            List {
                if searchText.isEmpty {
                    rootSections
                } else {
                    searchSection { result in
                        NavigationLink(value: result.page) {
                            SettingsPageRow(page: result.page, subtitle: matchesLine(result))
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Cerca nelle impostazioni")
            .navigationDestination(for: SettingsPage.self) { page in
                SettingsPageView(page: page)
            }
            .navigationTitle("Impostazioni")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
        .environment(router)
        #endif
    }

    // MARK: Ricerca

    private func matchesLine(_ result: SettingsSearchResult) -> String {
        result.matches.isEmpty ? result.page.subtitle : result.matches.joined(separator: " · ")
    }

    @ViewBuilder
    private func searchSection<Row: View>(
        @ViewBuilder row: @escaping (SettingsSearchResult) -> Row
    ) -> some View {
        if searchResults.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            Section("Risultati") {
                ForEach(searchResults) { result in
                    row(result)
                }
            }
        }
    }

    // MARK: macOS — barra laterale unica

    #if os(macOS)
    @ViewBuilder
    private var sidebarSections: some View {
        Section {
            SettingsAccountRow()
                .tag(SettingsPage.account)
        }
        Section("Generali") {
            ForEach(SettingsPage.generalPages) { page in
                SettingsPageRow(page: page)
                    .tag(page)
            }
        }
        Section {
            SettingsPageRow(page: .modules)
                .tag(SettingsPage.modules)
            ModuleRowLabel(module: .calendar, configuration: configuration)
                .tag(SettingsPage.module(.calendar))
            ForEach(reorderableModules) { module in
                ModuleRowLabel(module: module, configuration: configuration)
                    .tag(SettingsPage.module(module))
            }
            .onMove { source, destination in
                moveModules(from: source, to: destination, configurationRaw: &configurationRaw)
            }
        } header: {
            Text("Moduli")
        }
    }
    #endif

    // MARK: iPhone / iPad — elenco

    #if !os(macOS)
    @ViewBuilder
    private var rootSections: some View {
        Section {
            NavigationLink(value: SettingsPage.account) {
                SettingsAccountRow()
            }
        }
        Section("Generali") {
            ForEach(SettingsPage.generalPages) { page in
                NavigationLink(value: page) {
                    SettingsPageRow(page: page)
                }
            }
        }
        Section {
            NavigationLink(value: SettingsPage.modules) {
                SettingsPageRow(page: .modules, subtitle: "Accendi, spegni e riordina")
            }
            ForEach(configuration.moduleOrder) { module in
                NavigationLink(value: SettingsPage.module(module)) {
                    ModuleRowLabel(module: module, configuration: configuration)
                }
            }
        } header: {
            Text("Moduli")
        }
    }
    #endif
}

/// La pagina per ogni voce: un solo `switch`, usato da barra laterale,
/// elenco e ricerca.
struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .notifications: NotificationsSettingsView()
        case .sync: SyncSettingsView()
        case .account: AccountSettingsView()
        case .modules: ModulesOverviewView()
        case .module(let module): ModuleDetailView(module: module)
        }
    }
}

#if os(macOS)
/// La finestra Impostazioni (scena `Settings`, ⌘,) è una finestra normale:
/// cliccando sulla finestra principale finiva dietro e si perdeva. Un
/// pannello di preferenze nativo resta invece sempre davanti alla finestra
/// che l'ha aperta — qui si porta la finestra a livello `.floating` non
/// appena SwiftUI la crea, senza toccare `NSApp.activate` o altre finestre.
private struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            view.window?.level = .floating
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

#Preview {
    SettingsView()
        .modelContainer(PreviewSampleData.make().container)
}
