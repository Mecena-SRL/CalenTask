import SwiftUI
import SwiftData

/// Prima esperienza (S7/D68): utile in 60 secondi — crea il tuo spazio,
/// parti da un template, o entra e basta. Niente tour infiniti.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isCreatingWorkspace = false
    @State private var isCreatingProject = false

    var body: some View {
        VStack(spacing: DS.xl) {
            VStack(spacing: DS.s) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor.gradient)
                    .padding(.top, DS.xl)
                Text("Benvenuto in CalenTask")
                    .font(.dsScreenTitle)
                Text("Attività, calendario e produzioni in un posto solo.")
                    .font(.dsMeta)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DS.m) {
                welcomeRow(icon: "bolt.fill", tint: Color(hex: "#F76B15"),
                           title: "Cattura al volo",
                           subtitle: "Scrivi “montaggio domani alle 15 !alta” — capisce tutto lui.")
                welcomeRow(icon: "movieclapper", tint: Color(hex: "#E5484D"),
                           title: "Produzioni sul set",
                           subtitle: "Giorni di ripresa, troupe, scene e call sheet PDF — anche offline.")
                welcomeRow(icon: "calendar", tint: Color(hex: "#3E63DD"),
                           title: "Il tempo, sotto controllo",
                           subtitle: "Cinque viste calendario, meteo e time-blocking.")
            }
            .padding(.horizontal, DS.l)

            VStack(spacing: DS.s) {
                Button {
                    isCreatingProject = true
                } label: {
                    Text("Parti da un template")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsProminent)

                Button {
                    isCreatingWorkspace = true
                } label: {
                    Text("Crea lo spazio della tua società")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.dsGhost)

                Button("Inizia da zero") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.dsMeta)
                    .foregroundStyle(.secondary)
                    .padding(.top, DS.xs)
            }
            .padding([.horizontal, .bottom], DS.xl)
        }
        .frame(maxWidth: 440)
        .sheet(isPresented: $isCreatingWorkspace, onDismiss: { dismiss() }) {
            WorkspaceEditorView()
        }
        .sheet(isPresented: $isCreatingProject, onDismiss: { dismiss() }) {
            NewProjectSheet()
        }
    }

    private func welcomeRow(
        icon: String, tint: Color, title: String, subtitle: String
    ) -> some View {
        HStack(alignment: .top, spacing: DS.m) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.small))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dsRowTitle)
                Text(subtitle)
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WelcomeView()
        .modelContainer(PreviewSampleData.make().container)
}
