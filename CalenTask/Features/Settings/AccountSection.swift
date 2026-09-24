import SwiftUI
import SwiftData

/// Il tuo profilo, modificabile (richiesta v6). Lo stato di iCloud vive in
/// Impostazioni › Sincronizzazione (`ICloudStatusRow`). Quando arriverà il
/// backend multi-utente (Supabase), il login vivrà qui.
struct AccountSection: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<UserProfile> { $0.deletedAt == nil },
           sort: \UserProfile.createdAt)
    private var people: [UserProfile]

    private var me: UserProfile? { UserProfile.current(in: people) }

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
        } header: {
            Text("Profilo")
        } footer: {
            Text("Account multi-utente con login in arrivo: il profilo che imposti qui sarà la base. Lo stato di iCloud è in Sincronizzazione.")
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
