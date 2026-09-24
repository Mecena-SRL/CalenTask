import SwiftUI

/// Il momento di delight (E5/E6): il check fa bounce + haptic subito,
/// ma il commit (e quindi il collasso della riga nelle liste filtrate)
/// arriva dopo `commitDelay`. Un secondo tap nel frattempo annulla.
/// Riaprire un'attività completata è invece immediato.
struct DSCheckToggle: View {
    let isDone: Bool
    var font: Font = .title3
    var commitDelay: Duration = .seconds(2)
    let onCommit: () -> Void

    @State private var isPending = false
    @State private var pendingCommit: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shownDone: Bool { isDone || isPending }

    var body: some View {
        Button {
            if isPending {
                pendingCommit?.cancel()
                pendingCommit = nil
                withAnimation(.dsQuick) { isPending = false }
            } else if isDone {
                onCommit()
            } else {
                withAnimation(.dsQuick) { isPending = true }
                pendingCommit = Task {
                    try? await Task.sleep(for: commitDelay)
                    guard !Task.isCancelled else { return }
                    isPending = false
                    onCommit()
                }
            }
        } label: {
            Image(systemName: shownDone ? "checkmark.circle.fill" : "circle")
                .font(font)
                .foregroundStyle(shownDone ? DSColor.status(.done) : Color.secondary)
                .symbolEffect(.bounce, options: .speed(1.3),
                              value: reduceMotion ? false : shownDone)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: shownDone) { _, newValue in newValue }
        .accessibilityLabel(shownDone ? "Segna da fare" : "Segna completata")
        .onDisappear {
            // Se la riga sparisce (navigazione, refresh) il commit resta in volo:
            // il completamento non si perde, solo l'undo non è più offerto.
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var done = false
        var body: some View {
            HStack(spacing: DS.l) {
                DSCheckToggle(isDone: done) { done.toggle() }
                Text(done ? "Completata" : "Da fare")
            }
            .padding()
        }
    }
    return Demo()
}
