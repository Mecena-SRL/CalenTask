import SwiftUI

/// Un elemento in una riga di giorni (Mese, fascia "tutto il giorno" della
/// Settimana), secondo il tipo di segmento:
/// barra piena (più giorni / tutto il giorno, con i bordi "tagliati" se
/// continua), pallino·ora·titolo (evento con orario), bandierina (scadenza).
struct CalendarEventBar: View {
    let task: TodoTask
    let segment: CalendarWeekLayout.Segment

    @State private var isHovered = false

    private var tint: Color { Self.tint(for: task) }

    /// Colore di un elemento: etichetta in evidenza, poi progetto, poi accento.
    static func tint(for task: TodoTask) -> Color {
        task.accentTagColorHex.map { Color(hex: $0) }
            ?? task.project.map { Color(hex: $0.colorHex) }
            ?? .accentColor
    }

    var body: some View {
        TaskOpenLink(task: task) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .draggable(task.id.uuidString)
        .taskContextMenu(task)
        .onHover { isHovered = $0 }
        .help(helpText)
    }

    @ViewBuilder
    private var content: some View {
        switch segment.kind {
        case .span:
            HStack(spacing: 3) {
                if segment.continuesBefore {
                    Image(systemName: "chevron.left").font(.system(size: 7, weight: .bold))
                }
                Text(task.title)
                    .font(.system(size: 10, weight: .semibold))
                    .strikethrough(task.isDone)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if segment.continuesAfter {
                    Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold))
                }
            }
            .padding(.horizontal, 5)
            .foregroundStyle(task.isDone ? tint.opacity(0.6) : tint)
            .background(
                tint.opacity(task.isDone ? 0.08 : (isHovered ? 0.28 : 0.2)),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: segment.continuesBefore ? 0 : 4,
                    bottomLeadingRadius: segment.continuesBefore ? 0 : 4,
                    bottomTrailingRadius: segment.continuesAfter ? 0 : 4,
                    topTrailingRadius: segment.continuesAfter ? 0 : 4
                )
            )
        case .timed:
            HStack(spacing: 4) {
                Circle().fill(tint).frame(width: 6, height: 6)
                if let startAt = task.startAt {
                    Text(startAt.dsTimeLabel)
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(task.title)
                    .font(.system(size: 10, weight: .medium))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .background(isHovered ? tint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4))
        case .due:
            HStack(spacing: 4) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "flag.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(task.isOverdue ? DSColor.overdue : tint)
                Text(task.title)
                    .font(.system(size: 10, weight: .medium))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .background(isHovered ? tint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private var helpText: String {
        switch segment.kind {
        case .span, .timed:
            if let startAt = task.startAt {
                return "\(task.title) · \(startAt.appFormatted(.dateTime.weekday(.wide).day().month().hour().minute()))"
            }
            return task.title
        case .due:
            return "Scadenza: \(task.title)"
        }
    }
}
