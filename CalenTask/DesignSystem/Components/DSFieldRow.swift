import SwiftUI

/// Settings-style icon tile: white symbol on a tinted rounded square.
/// The anchor of every field row — keeps labels and values aligned (D17).
struct DSIconTile: View {
    let systemImage: String
    var tint: Color = .accentColor
    /// 28 nelle righe; più grande nelle testate (Impostazioni).
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemImage)
            .font(size == 28 ? .footnote.weight(.semibold) : .system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.25))
    }
}

/// Generic field row: icon tile + title (+ optional value subtitle) + trailing content.
/// Use this for every data field instead of ad-hoc HStacks.
struct DSFieldRow<Trailing: View>: View {
    let label: String
    let systemImage: String
    var tint: Color = .accentColor
    var value: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.m) {
            DSIconTile(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.dsMeta)
                    .foregroundStyle(.primary)
                if let value, !value.isEmpty {
                    Text(value)
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: DS.s)
            trailing
        }
        .contentShape(Rectangle())
    }
}

/// Text-input row: icon tile + full-width field with the label as inline
/// placeholder. On macOS a titled TextField inside a grouped Form renders as
/// "label left, squeezed right-aligned box" — this row keeps the input
/// leading-aligned and lets it grow with the text on every platform.
struct DSTextFieldRow: View {
    let label: String
    let systemImage: String
    var tint: Color = .accentColor
    @Binding var text: String

    var body: some View {
        HStack(spacing: DS.m) {
            DSIconTile(systemImage: systemImage, tint: tint)
            TextField("", text: $text, prompt: Text(label), axis: .vertical)
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(label)
    }
}

/// Bare text input that ALWAYS shows its label as inline placeholder and takes
/// the full row width — never the macOS Form "label left, box right" squeeze.
struct DSPromptField: View {
    let prompt: String
    @Binding var text: String
    var vertical = false

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt),
                  axis: vertical ? .vertical : .horizontal)
            .labelsHidden()
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(prompt)
    }
}

/// Notes editor: the whole area is clickable, writing starts top-leading and
/// the placeholder disappears with the first character (no dead "Note" label).
struct DSNotesEditor: View {
    @Binding var text: String
    var placeholder = "Note"
    var minHeight: CGFloat = 88

    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(.dsMeta)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.dsMeta)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
            .accessibilityLabel(placeholder)
    }
}

/// Elegant optional-date field: tap the row to set/expand, inline graphical
/// picker, clear affordance when set. Replaces the old toggle+picker squeeze.
struct DSDateField: View {
    let label: String
    let systemImage: String
    var tint: Color = .accentColor
    @Binding var date: Date?
    var includesTime = false

    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.dsQuick) {
                if date == nil {
                    date = defaultValue
                    isExpanded = true
                } else {
                    isExpanded.toggle()
                }
            }
        } label: {
            DSFieldRow(
                label: label,
                systemImage: systemImage,
                tint: date == nil ? Color.secondary.opacity(0.55) : tint,
                value: formattedValue
            ) {
                if date != nil {
                    Button {
                        withAnimation(.dsQuick) {
                            date = nil
                            isExpanded = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rimuovi \(label)")
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.tertiary)
                        .imageScale(.medium)
                }
            }
        }
        .buttonStyle(.plain)

        if isExpanded, date != nil {
            // Quick picks first — the calendar is the fallback, not the
            // protagonist (D24).
            quickChips

            DatePicker(
                label,
                selection: Binding(get: { date ?? .now }, set: { date = $0 }),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(tint)
            .padding(DS.s)
            .background(
                DSColor.surfaceSecondary.opacity(0.6),
                in: RoundedRectangle(cornerRadius: DS.Radius.small)
            )

            if includesTime {
                DSFieldRow(label: "Ora", systemImage: "clock", tint: tint) {
                    DatePicker(
                        "Ora",
                        selection: Binding(get: { date ?? .now }, set: { date = $0 }),
                        displayedComponents: [.hourAndMinute]
                    )
                    .labelsHidden()
                    .tint(tint)
                }
            }
        }
    }

    // MARK: Quick picks (D24)

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.s) {
                chip("Oggi", day: .now)
                chip("Domani", day: Calendar.app.date(byAdding: .day, value: 1, to: .now))
                chip("Weekend", day: nextWeekday(7))   // sabato
                chip("Lun. prossimo", day: nextWeekday(2))
            }
        }
    }

    private func chip(_ title: String, day: Date?) -> some View {
        let isSelected = day != nil && date != nil
            && Calendar.app.isDate(date!, inSameDayAs: day!)
        return Button {
            guard let day else { return }
            withAnimation(.dsQuick) { date = preservingTime(on: day) }
        } label: {
            Text(title)
                .font(.dsCaption.weight(.medium))
                .padding(.horizontal, DS.m)
                .padding(.vertical, DS.xs + 2)
                .background(isSelected ? tint : tint.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : tint)
        }
        .buttonStyle(.plain)
    }

    /// Changing the day keeps the chosen time of day.
    private func preservingTime(on day: Date) -> Date {
        let calendar = Calendar.app
        guard includesTime, let date else { return day.startOfDay }
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return calendar.date(
            bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day
        ) ?? day
    }

    private func nextWeekday(_ weekday: Int) -> Date? {
        Calendar.app.nextDate(
            after: .now,
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTime
        )
    }

    private var formattedValue: String? {
        guard let date else { return nil }
        let day = date.dsRelativeLabel
        return includesTime ? "\(day), \(date.dsTimeLabel)" : day
    }

    private var defaultValue: Date {
        if includesTime {
            let next = Calendar.app.date(byAdding: .hour, value: 1, to: .now) ?? .now
            return Calendar.app.date(bySetting: .minute, value: 0, of: next) ?? next
        }
        return .now.startOfDay
    }
}

/// Priority as a tinted flag menu — reads at a glance, no bare text picker.
struct DSPriorityField: View {
    @Binding var priority: TaskPriority

    var body: some View {
        DSFieldRow(
            label: "Priorità",
            systemImage: "flag.fill",
            tint: DSColor.priority(priority),
            value: nil
        ) {
            Menu {
                Picker("Priorità", selection: $priority) {
                    ForEach(TaskPriority.allCases.reversed()) { level in
                        Label(level.label, systemImage: "flag.fill").tag(level)
                    }
                }
            } label: {
                HStack(spacing: DS.xs) {
                    Text(priority.label)
                        .font(.dsMeta)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

#Preview("Campi data") {
    @Previewable @State var due: Date? = nil
    @Previewable @State var remind: Date? = .now
    @Previewable @State var priority: TaskPriority = .high
    return Form {
        Section("Date") {
            DSDateField(label: "Scadenza", systemImage: "flag", tint: .orange, date: $due)
            DSDateField(label: "Promemoria", systemImage: "bell", tint: .purple,
                        date: $remind, includesTime: true)
        }
        Section {
            DSPriorityField(priority: $priority)
        }
    }
    .formStyle(.grouped)
}
