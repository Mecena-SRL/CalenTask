import SwiftUI

struct TagChip: View {
    let name: String
    let colorHex: String

    init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }

    init(tag: Tag) {
        self.init(name: tag.name, colorHex: tag.colorHex)
    }

    var body: some View {
        Text(name)
            .font(.dsCaption)
            .padding(.horizontal, DS.s)
            .padding(.vertical, 2)
            .background(Color(hex: colorHex).opacity(0.14), in: Capsule())
            .foregroundStyle(Color(hex: colorHex))
    }
}

#Preview {
    HStack {
        TagChip(name: "set", colorHex: "#0E7490")
        TagChip(name: "urgente", colorHex: "#DC2626")
        TagChip(name: "amministrazione", colorHex: "#64748B")
    }
    .padding()
}
