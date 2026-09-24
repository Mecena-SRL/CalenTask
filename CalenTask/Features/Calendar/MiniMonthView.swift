import SwiftUI

/// Mese compatto per le viste Trimestre e Anno (D42): numeri, pallini di
/// densità, anello su oggi. Tap su un giorno → selezione.
struct MiniMonthView: View {
    let month: Date
    let selectedDay: Date
    /// Items per startOfDay — colora la densità.
    let countsByDay: [Date: Int]
    var showsTitle = true
    /// E10 — in vista Anno la densità diventa heatmap di sfondo (Timepage).
    var showsHeatmap = false
    var onSelectDay: (Date) -> Void = { _ in }
    var onSelectMonth: (Date) -> Void = { _ in }

    private let calendar = Calendar.app

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            if showsTitle {
                Button {
                    onSelectMonth(month)
                } label: {
                    Text(month.appFormatted(.dateTime.month(.wide)))
                        .font(.dsMeta.weight(.semibold))
                        .foregroundStyle(
                            CalendarMath.isSameMonth(month, .now, calendar: calendar)
                                ? Color.accentColor : .primary
                        )
                }
                .buttonStyle(.plain)
            }

            Grid(horizontalSpacing: 2, verticalSpacing: 3) {
                GridRow {
                    ForEach(CalendarMath.orderedWeekdaySymbols(calendar: calendar), id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(CalendarMath.monthGrid(for: month, calendar: calendar), id: \.first) { week in
                    GridRow {
                        ForEach(week, id: \.self) { day in
                            dayCell(day)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let inMonth = CalendarMath.isSameMonth(day, month, calendar: calendar)
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let count = countsByDay[day.startOfDay] ?? 0

        Button {
            onSelectDay(day)
        } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 10, weight: isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(
                        isToday ? Color.white
                            : inMonth ? Color.primary : Color.primary.opacity(0.25)
                    )
                    .frame(width: 18, height: 18)
                    .background {
                        if isToday {
                            Circle().fill(Color.accentColor)
                        } else if isSelected {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 1)
                        } else if showsHeatmap, inMonth, count > 0 {
                            Circle().fill(Color.accentColor.opacity(heatOpacity(count)))
                        }
                    }
                // F25 — i pallini restano anche con la heatmap attiva.
                Circle()
                    .fill(densityColor(count))
                    .frame(width: 3.5, height: 3.5)
                    .opacity(count > 0 && inMonth ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func densityColor(_ count: Int) -> Color {
        switch count {
        case 0: .clear
        case 1: Color.accentColor.opacity(0.45)
        case 2: Color.accentColor.opacity(0.75)
        default: Color.accentColor
        }
    }

    private func heatOpacity(_ count: Int) -> Double {
        switch count {
        case 0: 0
        case 1: 0.12
        case 2: 0.22
        default: 0.35
        }
    }
}

#Preview {
    MiniMonthView(month: .now, selectedDay: .now, countsByDay: [.now.startOfDay: 2])
        .frame(width: 160)
        .padding()
}
