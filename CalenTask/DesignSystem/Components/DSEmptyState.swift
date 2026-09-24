import SwiftUI

struct DSEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        // E12 — stati vuoti di sistema: ContentUnavailableView, mai layout ad-hoc.
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            if let subtitle { Text(subtitle) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.dsProminent)
            }
        }
    }
}

#Preview {
    DSEmptyState(
        icon: "tray",
        title: "Inbox vuota",
        subtitle: "Cattura un'idea con un tap.",
        actionTitle: "Nuova attività",
        action: {}
    )
}
