import SwiftUI
import SwiftData

// Mattoni di tutte le pagine di Impostazioni: stessa testata, stesse righe,
// così ogni pagina (anche quella di un modulo futuro) ha lo stesso aspetto.

/// Testata di pagina alla maniera di Impostazioni di Sistema: icona grande,
/// titolo, a cosa serve e, a destra, un controllo opzionale (l'interruttore
/// di un modulo).
struct SettingsPageHeader<Accessory: View>: View {
    let page: SettingsPage
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: DS.l) {
            DSIconTile(systemImage: page.systemImage, tint: page.tint, size: 48)
            VStack(alignment: .leading, spacing: DS.xs) {
                Text(page.title)
                    .font(.title3.weight(.semibold))
                Text(page.subtitle)
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.m)
            accessory
        }
        .padding(.vertical, DS.s)
    }
}

extension SettingsPageHeader where Accessory == EmptyView {
    init(page: SettingsPage) {
        self.init(page: page) { EmptyView() }
    }
}

/// Interruttore con icona, titolo e una riga che spiega cosa fa.
struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    let systemImage: String
    var tint: Color = .accentColor
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            DSFieldRow(label: title, systemImage: systemImage, tint: tint, value: detail) { EmptyView() }
        }
    }
}

/// Riga che apre qualcosa (un'altra pagina, un foglio): icona, titolo,
/// spiegazione e chevron.
struct SettingsLinkRow: View {
    let title: String
    var detail: String?
    let systemImage: String
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DSFieldRow(label: title, systemImage: systemImage, tint: tint, value: detail) {
                Image(systemName: "chevron.right")
                    .font(.dsCaption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Voce di una pagina nell'elenco principale (barra laterale su Mac).
struct SettingsPageRow: View {
    let page: SettingsPage
    var subtitle: String?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title)
                    .font(.dsMeta.weight(.medium))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            DSIconTile(systemImage: page.systemImage, tint: page.tint)
        }
        .padding(.vertical, 2)
    }
}

/// Testata dell'elenco: chi sei e dove vivono i tuoi dati, come la riga
/// Apple ID di Impostazioni di Sistema.
struct SettingsAccountRow: View {
    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil },
           sort: \UserProfile.createdAt)
    private var people: [UserProfile]

    private var name: String {
        if let me = UserProfile.current(in: people), !me.name.isEmpty { return me.name }
        return "Il tuo profilo"
    }

    var body: some View {
        HStack(spacing: DS.m) {
            AccountAvatar(name: name, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.dsMeta.weight(.semibold))
                    .lineLimit(1)
                Label(
                    StoreMode.isCloudKit ? "iCloud attivo" : "Solo su questo dispositivo",
                    systemImage: StoreMode.isCloudKit ? "checkmark.icloud" : "internaldrive"
                )
                .font(.dsCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, DS.xs)
    }
}

/// Stato reale della sincronizzazione iCloud (lo store aperto, non solo
/// "c'è un Apple ID"), con il motivo se CloudKit non si è aperto (#17).
struct ICloudStatusRow: View {
    private var isActive: Bool { StoreMode.isCloudKit }

    private var detail: String {
        if isActive { return "I dati seguono il tuo Apple ID su Mac e iPhone." }
        if let failure = StoreMode.cloudKitFailure {
            return "iCloud non si è aperto (\(failure)): i dati restano solo su questo dispositivo."
        }
        if FileManager.default.ubiquityIdentityToken != nil {
            return "Apple ID collegato, ma questa build usa lo store locale (simulatore o firma senza iCloud)."
        }
        return "Accedi a iCloud nelle impostazioni di sistema."
    }

    var body: some View {
        DSFieldRow(
            label: isActive ? "iCloud attivo" : "iCloud non attivo",
            systemImage: isActive ? "checkmark.icloud.fill" : "xmark.icloud",
            tint: isActive ? .cyan : .orange,
            value: detail
        ) { EmptyView() }
    }
}

extension UserProfile {
    /// Il profilo di chi usa questo dispositivo (id salvato dal seed), o il
    /// primo se manca.
    static func current(in people: [UserProfile]) -> UserProfile? {
        let currentID = UserDefaults.standard.string(forKey: SeedService.userDefaultsKey)
            .flatMap(UUID.init(uuidString:))
        return people.first { $0.id == currentID } ?? people.first
    }
}

// MARK: Binding sulla configurazione salvata

extension AppConfiguration {
    /// Interruttore di una funzione che riscrive la configurazione salvata.
    static func binding(for feature: AppFeature, in raw: Binding<String>) -> Binding<Bool> {
        Binding(get: { decode(raw.wrappedValue).isEnabled(feature) }, set: { value in
            var updated = decode(raw.wrappedValue)
            updated.set(feature, enabled: value)
            raw.wrappedValue = updated.encoded()
        })
    }

    /// Interruttore di un modulo.
    static func binding(for module: AppModule, in raw: Binding<String>) -> Binding<Bool> {
        Binding(get: { decode(raw.wrappedValue).isEnabled(module) }, set: { value in
            var updated = decode(raw.wrappedValue)
            updated.set(module, enabled: value)
            raw.wrappedValue = updated.encoded()
        })
    }

    /// Schermata iniziale (Rapida solo se il modulo Attività è acceso).
    static func startPageBinding(in raw: Binding<String>) -> Binding<AppStartPage> {
        Binding(get: {
            let configuration = decode(raw.wrappedValue)
            return configuration.startPage == .quick && !configuration.isEnabled(.activities)
                ? .calendar : configuration.startPage
        }, set: { value in
            var updated = decode(raw.wrappedValue)
            updated.startPage = value
            raw.wrappedValue = updated.encoded()
        })
    }
}
