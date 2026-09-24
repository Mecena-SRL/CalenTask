import SwiftUI

struct StatTile: View {
    let title: String
    let count: Int
    let icon: String
    var tint: Color = .accentColor
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: DS.s) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                    Spacer()
                }
                Text("\(count)")
                    .font(.dsStatNumber)
                    .foregroundStyle(count > 0 ? tint : Color.secondary)
                    .contentTransition(.numericText())
                    .animation(.dsQuick, value: count)
                Text(title)
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(DS.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSurface(.card)
        }
        .buttonStyle(.plain)
        .dsHoverHighlight(cornerRadius: DS.Radius.medium)
    }
}

#Preview {
    HStack(spacing: DS.m) {
        StatTile(title: "In ritardo", count: 2, icon: "exclamationmark.circle", tint: DSColor.overdue)
        StatTile(title: "Oggi", count: 5, icon: "sun.max")
        StatTile(title: "Inbox", count: 3, icon: "tray")
    }
    .padding()
}
