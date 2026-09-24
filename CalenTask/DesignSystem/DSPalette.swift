import SwiftUI

/// La palette vivida condivisa (progetti, spazi, etichette): 10 tinte
/// nominate, scelte per reggere bene in chiaro e scuro. Il colore resta un
/// evento (E2) — ma quando c'è, deve essere vivo, non spento.
enum DSPalette {
    struct Swatch: Identifiable, Equatable {
        let name: String
        let hex: String
        var id: String { hex }
        var color: Color { Color(hex: hex) }
    }

    static let swatches: [Swatch] = [
        Swatch(name: "Rosso", hex: "#E5484D"),
        Swatch(name: "Arancio", hex: "#F76B15"),
        Swatch(name: "Ambra", hex: "#FFB224"),
        Swatch(name: "Verde", hex: "#30A46C"),
        Swatch(name: "Smeraldo", hex: "#12A594"),
        Swatch(name: "Ciano", hex: "#0EA5E9"),
        Swatch(name: "Blu", hex: "#3E63DD"),
        Swatch(name: "Viola", hex: "#6E56CF"),
        Swatch(name: "Magenta", hex: "#D6409F"),
        Swatch(name: "Ardesia", hex: "#64748B"),
    ]

    static var randomHex: String { swatches.randomElement()!.hex }
}

/// Griglia di scelta colore riusabile (spazi, progetti): swatch tondi,
/// anello sul selezionato, niente ColorPicker di sistema (palette curata).
struct DSPaletteGrid: View {
    @Binding var selectedHex: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: DS.m) {
            ForEach(DSPalette.swatches) { swatch in
                Button {
                    withAnimation(.dsQuick) { selectedHex = swatch.hex }
                } label: {
                    Circle()
                        .fill(swatch.color.gradient)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if selectedHex.lowercased() == swatch.hex.lowercased() {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 2)
                                    .padding(3)
                            }
                        }
                        .overlay {
                            Circle().strokeBorder(DSColor.hairline)
                        }
                }
                .buttonStyle(.plain)
                .help(swatch.name)
                .accessibilityLabel(swatch.name)
            }
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var hex = "#12A594"
        var body: some View { DSPaletteGrid(selectedHex: $hex).padding() }
    }
    return Demo()
}
