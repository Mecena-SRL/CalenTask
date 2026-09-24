import SwiftUI
import SwiftData
#if os(macOS)
import Security
#endif

/// Il mirroring CloudKit SIGTRAPpa in asincrono (non catturabile) se il
/// processo non ha l'entitlement iCloud: succede nel simulatore e nelle
/// build macOS firmate senza provisioning (es. da terminale). Qui si
/// controlla PRIMA di scegliere lo store cloud. Su device iOS reali
/// l'entitlement arriva sempre col profilo, altrimenti l'install fallisce.
/// Modalità EFFETTIVA dello store (audit account A6, 2026-09-10): prima la UI
/// deduceva "iCloud attivo" solo dalla presenza di un Apple ID di sistema
/// (`ubiquityIdentityToken`), che dice nulla su quale container SwiftData ha
/// davvero aperto — sul simulatore, o senza entitlement, lo store è SEMPRE
/// locale anche con un Apple ID collegato. Impostata una sola volta, qui,
/// quando si sceglie davvero la configurazione CloudKit.
enum StoreMode {
    static fileprivate(set) var isCloudKit = false
}

private func processHasCloudKitEntitlement() -> Bool {
    #if targetEnvironment(simulator)
    return false
    #elseif os(macOS)
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    let value = SecTaskCopyValueForEntitlement(
        task, "com.apple.developer.icloud-services" as CFString, nil
    )
    return value != nil
    #else
    return true
    #endif
}

@main
struct CalenTaskApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    private let router = AppRouter.shared
    @AppStorage(AppConfiguration.storageKey) private var configurationRaw = ""
    private var configuration: AppConfiguration { .decode(configurationRaw) }

    /// Tema scelto dall'utente (D47): auto, chiaro, scuro, misto.
    @AppStorage(DSAppearance.storageKey) private var appearanceRaw = DSAppearance.auto.rawValue

    /// iCloud container per la sync Mac ↔ iPhone (D45-bis).
    static let cloudKitContainerID = "iCloud.it.mecena.CalenTask"

    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: CalenTaskSchemaV10.self)

        // 1ª scelta: database privato CloudKit — stessa vita su Mac e iPhone.
        // Migrazione AUTOMATICA lightweight (fix v7): il piano a stadi
        // crashava su store esistenti e CloudKit comunque non lo supporta.
        if processHasCloudKitEntitlement() {
            let cloudConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            do {
                let container = try ModelContainer(
                    for: schema,
                    configurations: [cloudConfiguration]
                )
                StoreMode.isCloudKit = true
                return container
            } catch {
                // Fallback locale: l'app deve aprirsi anche senza iCloud
                // (utente non loggato, container danneggiato, ecc.).
                print("⚠️ CloudKit non disponibile, store locale: \(error)")
            }
        } else {
            print("ℹ️ Processo senza entitlement iCloud: store locale.")
        }

        let localConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(
                for: schema,
                configurations: [localConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(router)
                .preferredColorScheme(
                    (DSAppearance(rawValue: appearanceRaw) ?? .auto).colorScheme
                )
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Cattura rapida") {
                    router.isQuickCaptureOpen = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                if configuration.isEnabled(.externalRequests) {
                Button("Nuova richiesta…") {
                    router.isIntakeOpen = true
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Nuova attività") {
                    router.isQuickCaptureOpen = true
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Cerca ovunque (⌘K)") {
                    router.isCommandPaletteOpen = true
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            // D74 — il pannello Oggi si governa dal menu Vista (⌥⌘0).
            CommandGroup(after: .sidebar) {
                if configuration.isEnabled(.todayInspector) {
                Button("Pannello Oggi") {
                    let defaults = UserDefaults.standard
                    let current = defaults.object(forKey: TodayPanel.storageKey)
                        as? Bool ?? true
                    defaults.set(!current, forKey: TodayPanel.storageKey)
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                }
            }
            CommandMenu("Vai") {
                ForEach(Array(configuration.navigationSections.enumerated()), id: \.element.id) { index, section in
                    Button(section.label) {
                        router.go(section)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            #if DEBUG
            CommandMenu("Debug") {
                Button("Genera 500 attività di prova") {
                    try? DebugSeeder.generate(in: sharedModelContainer.mainContext)
                }
            }
            #endif
        }
        #endif

        #if os(macOS)
        MenuBarExtra("CalenTask", systemImage: "tray.and.arrow.down") {
            MenuBarCaptureView()
        }
        .menuBarExtraStyle(.window)
        .modelContainer(sharedModelContainer)

        // Impostazioni native (⌘,) — D43.
        Settings {
            SettingsView()
        }
        .modelContainer(sharedModelContainer)
        #endif
    }
}
