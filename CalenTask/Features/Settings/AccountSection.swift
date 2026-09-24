import SwiftUI
import SwiftData

/// Il tuo account, sempre a portata di mano (richiesta v6): profilo
/// modificabile + stato della sincronizzazione iCloud. Quando arriverà il
/// backend multi-utente (Supabase), il login vivrà qui.
struct AccountSection: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil },
           sort: \UserProfile.createdAt)
    private var people: [UserProfile]

    private var me: UserProfile? {
        let currentID = UserDefaults.standard.string(forKey: SeedService.userDefaultsKey)
            .flatMap(UUID.init(uuidString:))
        return people.first { $0.id == currentID } ?? people.first
    }

    /// A6 (audit account): la modalità EFFETTIVA dello store — non "c'è un
    /// Apple ID collegato" (`ubiquityIdentityToken`), che è vero anche
    /// quando lo store è locale (simulatore, entitlement mancante).
    private var isICloudActive: Bool {
        StoreMode.isCloudKit
    }

    /// Un Apple ID è collegato al sistema, indipendentemente da quale store
    /// l'app abbia davvero aperto: distinto apposta da `isICloudActive`.
    private var hasSystemICloudAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var icloudDetail: String {
        if isICloudActive {
            return "I dati seguono il tuo Apple ID su Mac e iPhone"
        }
        if hasSystemICloudAccount {
            return "Apple ID collegato, ma questa build usa lo store locale (simulatore o firma senza iCloud)"
        }
        return "Accedi a iCloud nelle impostazioni di sistema"
    }

    var body: some View {
        Section {
            if let me {
                HStack(spacing: DS.l) {
                    AccountAvatar(name: me.name, size: 52)
                    VStack(alignment: .leading, spacing: DS.xs) {
                        TextField("Nome", text: Binding(
                            get: { me.name },
                            set: { me.name = $0; me.updatedAt = .now }
                        ))
                        .textFieldStyle(.plain)
                        .font(.dsRowTitle)
                        TextField("Email", text: Binding(
                            get: { me.email },
                            set: { me.email = $0; me.updatedAt = .now }
                        ))
                        .textFieldStyle(.plain)
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    }
                }
                .padding(.vertical, DS.xs)
            }

            DSFieldRow(
                label: isICloudActive ? "Sincronizzazione iCloud" : "iCloud non attivo",
                systemImage: isICloudActive ? "checkmark.icloud.fill" : "xmark.icloud",
                tint: isICloudActive ? .cyan : .orange
            ) {
                Text(icloudDetail)
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Account multi-utente con login in arrivo: il profilo che imposti qui sarà la base.")
                .font(.dsCaption)
        }
    }
}

/// Avatar a iniziali, coerente ovunque (sidebar, team, account).
struct AccountAvatar: View {
    let name: String
    var size: CGFloat = 30

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first)
        return parts.isEmpty ? "?" : parts.map(String.init).joined()
    }

    private var tint: Color {
        Color(hex: TagService.defaultPalette[abs(name.hashValue) % TagService.defaultPalette.count])
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: Circle())
    }
}

#Preview {
    Form { AccountSection() }
        .formStyle(.grouped)
        .modelContainer(PreviewSampleData.make().container)
}
