import SwiftUI

/// Monday-style status pill: solid color, white bold text (D35/estetica v4).
struct StatusBadge: View {
    let status: TaskStatus

    var body: some View {
        Text(status.label)
            .font(.dsCaption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.s + 1)
            .padding(.vertical, 3)
            .background(DSColor.status(status).gradient, in: RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    HStack {
        ForEach(TaskStatus.allCases) { StatusBadge(status: $0) }
    }
    .padding()
}
