import SwiftUI

struct DSCard<Content: View>: View {
    var level: DSElevation = .card
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(DS.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSurface(level)
    }
}

#Preview {
    DSCard {
        VStack(alignment: .leading, spacing: DS.s) {
            Text("Oggi").font(.dsSectionTitle)
            Text("3 attività").font(.dsMeta).foregroundStyle(.secondary)
        }
    }
    .padding()
}
