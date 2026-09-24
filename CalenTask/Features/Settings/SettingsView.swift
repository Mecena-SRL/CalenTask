import SwiftUI
import SwiftData

/// Impostazioni (D43): tutte le personalizzazioni in un posto solo.
/// macOS: scena Settings (⌘,). iOS: sheet dall'ingranaggio.
#if os(macOS)
/// Una sola voce nella barra laterale di Impostazioni — non due contenitori
/// di navigazione annidati (era il bug: `NavigationSplitView` dentro una
/// `TabView` rompeva sia il pulsante indietro sia il click sulle altre tab).
private enum SettingsDestination: Hashable {
    case appearance
    case account
    case module(AppModule)
}
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Aspetto (D47)
    @AppStorage(DSAppearance.storageKey) private var appearanceRaw = DSAppearance.auto.rawValue

    #if os(macOS)
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    private var configuration: AppConfiguration { .decode(configurationRaw) }
    @State private var selection: SettingsDestination? = .module(.calendar)

    private var reorderableModules: [AppModule] {
        configuration.moduleOrder.filter { $0 != .calendar }
    }
    #endif

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selection) {
                Section("Generali") {
                    settingsRow("Aspetto", systemImage: "paintbrush", tint: Color(hex: "#5B5BD6"))
                        .tag(SettingsDestination.appearance)
                    settingsRow("Account e spazi", systemImage: "person.crop.circle", tint: Color(hex: "#30A46C"))
                        .tag(SettingsDestination.account)
                }
                Section("La tua app") {
                    Picker("All'avvio", selection: startPageBinding) {
                        ForEach(AppStartPage.allCases.filter {
                            $0 != .quick || configuration.isEnabled(.activities)
                        }) { page in
                            Text(page.title).tag(page)
                        }
                    }
                }
                Section {
                    ModuleRowLabel(module: .calendar, configuration: configuration)
                        .tag(SettingsDestination.module(.calendar))
                    ForEach(reorderableModules) { module in
                        ModuleRowLabel(module: module, configuration: configuration)
                            .tag(SettingsDestination.module(module))
                    }
                    .onMove { source, destination in
                        moveModules(from: source, to: destination, configurationRaw: &configurationRaw)
                    }
                } header: {
                    Text("Moduli")
                } footer: {
                    Text("Trascina per riordinare: lo stesso ordine vale nella barra laterale dell'app.")
                }
                Section {
                    Button("Ripristina configurazione essenziale") {
                        configurationRaw = AppConfiguration.standard.encoded()
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            settingsDetail
        }
        // Come Impostazioni di Sistema: la barra laterale non si chiude. Il
        // toggle di sistema sparisce dalla toolbar; la larghezza minima sopra
        // impedisce anche di trascinarla a zero.
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 640)
        .background(FloatingWindowConfigurator())
        #else
        NavigationStack {
            Form {
                Section {
                    NavigationLink { appearanceTab.navigationTitle("Aspetto") } label: {
                        iOSSettingsRow("Aspetto", systemImage: "paintbrush", tint: Color(hex: "#5B5BD6"))
                    }
                    NavigationLink { accountTab.navigationTitle("Account e spazi") } label: {
                        iOSSettingsRow("Account e spazi", systemImage: "person.crop.circle", tint: Color(hex: "#30A46C"))
                    }
                }
                Section {
                    NavigationLink { ModulesSettingsView() } label: {
                        iOSSettingsRow("Moduli e schermata iniziale", systemImage: "square.grid.2x2", tint: Color.accentColor)
                    }
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
        #endif
    }

    // MARK: macOS — barra laterale unica

    #if os(macOS)
    /// Riga della barra laterale nello stesso linguaggio dei moduli sotto:
    /// badge colorato (`DSIconTile`, lo stesso di ogni campo nei form) invece
    /// di un'icona piatta — coerente, non un'aggiunta ad hoc.
    private func settingsRow(_ title: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title).font(.dsMeta.weight(.medium))
        } icon: {
            DSIconTile(systemImage: systemImage, tint: tint)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var settingsDetail: some View {
        switch selection {
        case .appearance: appearanceTab.navigationTitle("Aspetto")
        case .account: accountTab.navigationTitle("Account e spazi")
        case .module(let module): ModuleDetailView(module: module)
        case nil:
            ContentUnavailableView(
                "Seleziona una voce",
                systemImage: "gearshape",
                description: Text("Scegli una categoria dalla barra laterale.")
            )
        }
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
    #endif

    private var accountTab: some View { Form { AccountSection(); WorkspacesSettingsSection() }.formStyle(.grouped) }
    private var appearanceTab: some View { Form { appearanceSections }.formStyle(.grouped) }

    private func iOSSettingsRow(_ title: String, systemImage: String, tint: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            DSIconTile(systemImage: systemImage, tint: tint)
        }
    }

    // MARK: Aspetto (D47) — tema alla maniera di Impostazioni di Sistema

    @ViewBuilder
    private var appearanceSections: some View {
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
            Text("Misto: sidebar scura, contenuto chiaro o secondo il sistema.")
                .font(.dsCaption)
            #endif
        }
    }

    private func appearanceCard(_ appearance: DSAppearance) -> some View {
        let isSelected = appearanceRaw == appearance.rawValue
        return Button {
            withAnimation(.dsQuick) { appearanceRaw = appearance.rawValue }
        } label: {
            VStack(spacing: DS.s) {
                Image(systemName: appearance.systemImage)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 52, height: 36)
                    .background(
                        DSColor.surfaceSecondary,
                        in: RoundedRectangle(cornerRadius: DS.Radius.small)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.small)
                            .strokeBorder(
                                isSelected ? Color.accentColor : DSColor.hairline,
                                lineWidth: isSelected ? 2 : 1
                            )
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
