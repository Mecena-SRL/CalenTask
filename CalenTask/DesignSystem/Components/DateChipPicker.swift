import SwiftUI

/// Fast date selection: Oggi / Domani / Settimana prossima / Scegli…
struct DateChipPicker: View {
    let label: String
    @Binding var date: Date?
    @State private var showsCustomPicker = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.s) {
                chip("Oggi", target: Date.now.startOfDay)
                chip("Domani", target: Calendar.app.date(byAdding: .day, value: 1, to: .now.startOfDay))
                chip("Settimana pross.", target: nextMonday)
                customChip
                if date != nil {
                    Button {
                        date = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rimuovi \(label)")
                }
            }
        }
        .popover(isPresented: $showsCustomPicker) {
            DatePicker(label, selection: Binding(
                get: { date ?? .now },
                set: { date = $0 }
            ), displayedComponents: [.date])
            .datePickerStyle(.graphical)
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }

    private var nextMonday: Date? {
        Calendar.app.nextDate(
            after: .now,
            matching: DateComponents(weekday: 2),
            matchingPolicy: .nextTime
        )?.startOfDay
    }

    private func chip(_ title: String, target: Date?) -> some View {
        let isSelected = target != nil && date != nil
            && Calendar.app.isDate(date!, inSameDayAs: target!)
        return Button {
            date = target
        } label: {
            Text(title)
                .font(.dsCaption.weight(.medium))
                .padding(.horizontal, DS.m)
                .padding(.vertical, DS.xs + 2)
                .background(
                    isSelected ? Color.accentColor : Color.accentColor.opacity(0.1),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var customChip: some View {
        Button {
            showsCustomPicker = true
        } label: {
            Text(customLabel)
                .font(.dsCaption.weight(.medium))
                .padding(.horizontal, DS.m)
                .padding(.vertical, DS.xs + 2)
                .background(
                    isCustomSelected ? Color.accentColor : Color.accentColor.opacity(0.1),
                    in: Capsule()
                )
                .foregroundStyle(isCustomSelected ? Color.white : Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var isCustomSelected: Bool {
        guard let date else { return false }
        let calendar = Calendar.app
        let isQuick = calendar.isDateInToday(date) || calendar.isDateInTomorrow(date)
            || (nextMonday.map { calendar.isDate(date, inSameDayAs: $0) } ?? false)
        return !isQuick
    }

    private var customLabel: String {
        if isCustomSelected, let date { return date.dsRelativeLabel }
        return "Scegli…"
    }
}

#Preview {
    @Previewable @State var date: Date? = nil
    return DateChipPicker(label: "Scadenza", date: $date)
        .padding()
}
