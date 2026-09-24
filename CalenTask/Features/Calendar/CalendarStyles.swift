import SwiftUI

// I tipi di visualizzazione di ogni scala e il selettore a capsula comune.

/// Un tipo di visualizzazione: titolo e icona per il selettore.
protocol CalendarStyleOption: Hashable, Identifiable, CaseIterable where AllCases == [Self] {
    var title: String { get }
    var systemImage: String { get }
}

/// Giorno: agenda (elenco) o griglia oraria (time-blocking).
enum CalendarDayStyle: String, CalendarStyleOption {
    case agenda, grid

    static let storageKey = "calendarDayMode"
    var id: String { rawValue }
    var title: String { self == .agenda ? "Agenda" : "Griglia" }
    var systemImage: String { self == .agenda ? "list.bullet" : "calendar.day.timeline.left" }
}

/// Settimana: griglia oraria o colonne (planner senza ore).
enum CalendarWeekStyle: String, CalendarStyleOption {
    case grid, columns

    static let storageKey = "calendarWeekStyle"
    var id: String { rawValue }
    var title: String { self == .grid ? "Griglia oraria" : "Colonne" }
    var systemImage: String { self == .grid ? "calendar.day.timeline.leading" : "rectangle.split.3x1" }
}

/// Mese: griglia o elenco (agenda del mese).
enum CalendarMonthStyle: String, CalendarStyleOption {
    case grid, list

    static let storageKey = "calendarMonthStyle"
    var id: String { rawValue }
    var title: String { self == .grid ? "Griglia" : "Elenco" }
    var systemImage: String { self == .grid ? "calendar" : "list.bullet.below.rectangle" }
}

/// Selettore a capsula: la pillola colorata scivola sull'opzione scelta.
/// `compact` mostra solo le icone (con il titolo come aiuto).
struct CalendarStyleToggle<Option: CalendarStyleOption>: View {
    @Binding var selection: Option
    var compact = false

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Option.allCases) { option in
                segment(option)
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.4), in: Capsule())
    }

    private func segment(_ option: Option) -> some View {
        let isOn = option == selection
        return Button {
            withAnimation(.dsQuick) { selection = option }
        } label: {
            Group {
                if compact {
                    Image(systemName: option.systemImage)
                } else {
                    Label(option.title, systemImage: option.systemImage)
                }
            }
            .font(.dsCaption.weight(.medium))
            .padding(.horizontal, compact ? DS.s + 2 : DS.m)
            .padding(.vertical, DS.xs + 1)
            .background {
                if isOn {
                    Capsule()
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(option.title)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
