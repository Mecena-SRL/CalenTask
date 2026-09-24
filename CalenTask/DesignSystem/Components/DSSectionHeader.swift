import SwiftUI

struct DSSectionHeader: View {
    let title: String
    var count: Int? = nil
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: DS.s) {
            Text(title)
                .font(.dsSectionTitle)
                .foregroundStyle(tint)
            if let count {
                Text("\(count)")
                    .font(.dsNumeric.weight(.semibold))
                    .padding(.horizontal, DS.s)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    VStack(spacing: DS.l) {
        DSSectionHeader(title: "In ritardo", count: 2, tint: DSColor.overdue)
        DSSectionHeader(title: "Oggi", count: 5)
        DSSectionHeader(title: "In corso")
    }
    .padding()
}
