import SwiftUI

/// Small priority indicator; hidden for .normal to keep rows quiet.
struct PriorityDot: View {
    let priority: TaskPriority

    var body: some View {
        if priority != .normal {
            Circle()
                .fill(DSColor.priority(priority))
                .frame(width: 8, height: 8)
                .accessibilityLabel("Priorità \(priority.label)")
        }
    }
}

#Preview {
    HStack(spacing: DS.m) {
        ForEach(TaskPriority.allCases) { PriorityDot(priority: $0) }
    }
    .padding()
}
