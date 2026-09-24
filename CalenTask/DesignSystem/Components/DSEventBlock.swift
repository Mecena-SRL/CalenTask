import SwiftUI

/// E4 — La ricetta blocco-evento unica: fill tinta 15% + bordo sinistro 3pt
/// + radius 8 + testo nella tinta. Identica in giorno, settimana e mese.
private struct DSEventBlockModifier: ViewModifier {
    let tint: Color
    var isDone = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isDone ? tint.opacity(0.55) : tint)
            .background(
                tint.opacity(isDone ? 0.07 : 0.15),
                in: RoundedRectangle(cornerRadius: DS.Radius.small)
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: DS.Radius.small,
                    bottomLeadingRadius: DS.Radius.small
                )
                .fill(tint.opacity(isDone ? 0.35 : 1))
                .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.small))
    }
}

extension View {
    func dsEventBlock(tint: Color, isDone: Bool = false) -> some View {
        modifier(DSEventBlockModifier(tint: tint, isDone: isDone))
    }
}

/// E10 — Linea "adesso": pallino + linea piena solo su oggi,
/// versione sbiadita (senza pallino) sugli altri giorni della settimana.
struct DSNowLine: View {
    var isProminent = true

    var body: some View {
        HStack(spacing: DS.xs) {
            if isProminent {
                Circle().fill(DSColor.overdue).frame(width: 7, height: 7)
            }
            Rectangle()
                .fill(DSColor.overdue.opacity(isProminent ? 1 : 0.25))
                .frame(height: isProminent ? 1.5 : 1)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: DS.l) {
        Text("Riunione produzione\n10:00 – 11:30")
            .font(.dsCaption.weight(.semibold))
            .padding(DS.s)
            .frame(width: 180, alignment: .leading)
            .dsEventBlock(tint: .teal)
        Text("Color grading")
            .font(.dsCaption.weight(.semibold))
            .padding(DS.s)
            .frame(width: 180, alignment: .leading)
            .dsEventBlock(tint: .orange, isDone: true)
        DSNowLine().frame(width: 200)
        DSNowLine(isProminent: false).frame(width: 200)
    }
    .padding()
}
