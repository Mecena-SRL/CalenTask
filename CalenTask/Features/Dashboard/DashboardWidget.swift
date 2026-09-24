import SwiftUI

/// Widget disponibili nella Home. Ogni modulo aggiunge solo le sezioni
/// pertinenti; ordine, visibilità e larghezze restano personali.
enum DashboardWidget: String, CaseIterable, Identifiable {
    case urgent
    case today
    case upcoming
    case advice
    case trend
    case health
    case timeline
    case workload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .urgent: "Urgenti"
        case .today: "Oggi"
        case .upcoming: "In arrivo"
        case .advice: "Suggerimenti"
        case .trend: "Andamento"
        case .health: "Salute progetti"
        case .timeline: "Prossimi 30 giorni"
        case .workload: "Carico di lavoro"
        }
    }

    var icon: String {
        switch self {
        case .urgent: "flag.fill"
        case .today: "sun.max"
        case .upcoming: "tray.and.arrow.down"
        case .advice: "lightbulb"
        case .trend: "chart.line.uptrend.xyaxis"
        case .health: "chart.bar.xaxis"
        case .timeline: "calendar.badge.clock"
        case .workload: "gauge.with.dots.needle.50percent"
        }
    }

    func isAvailable(in configuration: AppConfiguration) -> Bool {
        switch self {
        case .urgent, .today, .upcoming:
            true
        case .advice, .trend, .workload:
            configuration.isEnabled(.insights)
        case .health, .timeline:
            configuration.isEnabled(.projects)
        }
    }
}

/// Quanto è largo un widget (D94): una colonna, due, o l'intera riga. È
/// relativa al layout — "Intera riga" a 3 colonne ne occupa 3, a 2 ne
/// occupa 2 — così la stessa scelta funziona a ogni taglia.
enum WidgetWidth: String, CaseIterable, Identifiable {
    case single
    case double
    case full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: "Una colonna"
        case .double: "Due colonne"
        case .full: "Intera riga"
        }
    }

    var icon: String {
        switch self {
        case .single: "rectangle"
        case .double: "rectangle.split.2x1"
        case .full: "rectangle.fill"
        }
    }

    /// Quante colonne occupa, dato il numero di colonne disponibili.
    func span(columns: Int) -> Int {
        switch self {
        case .single: 1
        case .double: min(2, columns)
        case .full: columns
        }
    }
}

/// Stato persistito del cruscotto: un ordine per ciascun numero di colonne
/// + l'insieme dei widget nascosti e la larghezza scelta per widget
/// (condivise tra i layout). Tiene insieme lettura, scrittura e riordino in
/// un posto solo, testabile.
enum DashboardLayout {
    static let hiddenKey = "dashboard.widgetHidden"
    static let widthKey = "dashboard.widgetWidth"
    static let defaultOrder: [DashboardWidget] = [
        .today, .upcoming, .urgent, .advice, .trend, .health, .timeline, .workload
    ]

    /// Chiave dell'ordine per un dato numero di colonne (1, 2 o 3).
    static func orderKey(columns: Int) -> String {
        "dashboard.widgetOrder.\(columns)"
    }

    /// L'ordine salvato, completato con eventuali widget nuovi (aggiunti in
    /// coda) e ripulito da raw sconosciuti.
    static func order(from raw: String) -> [DashboardWidget] {
        var seen = Set<DashboardWidget>()
        var result = raw.split(separator: ",")
            .compactMap { DashboardWidget(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
        for widget in defaultOrder where !result.contains(widget) {
            result.append(widget)
        }
        return result
    }

    static func hidden(from raw: String) -> Set<DashboardWidget> {
        Set(raw.split(separator: ",").compactMap { DashboardWidget(rawValue: String($0)) })
    }

    static func encode(order: [DashboardWidget]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }

    static func encode(hidden: Set<DashboardWidget>) -> String {
        hidden.map(\.rawValue).joined(separator: ",")
    }

    /// Larghezze per widget, formato "widget:width,widget:width".
    static func widths(from raw: String) -> [DashboardWidget: WidgetWidth] {
        var result: [DashboardWidget: WidgetWidth] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: ":")
            if parts.count == 2,
               let widget = DashboardWidget(rawValue: String(parts[0])),
               let width = WidgetWidth(rawValue: String(parts[1])) {
                result[widget] = width
            }
        }
        return result
    }

    static func encode(widths: [DashboardWidget: WidgetWidth]) -> String {
        widths.map { "\($0.key.rawValue):\($0.value.rawValue)" }.joined(separator: ",")
    }

    /// Sposta `dragged` nella posizione di `target` mantenendo l'ordine
    /// intuitivo (trascinando verso il basso si finisce DOPO il bersaglio,
    /// verso l'alto PRIMA).
    static func reordering(_ order: [DashboardWidget],
                           moving dragged: DashboardWidget,
                           to target: DashboardWidget) -> [DashboardWidget] {
        guard dragged != target,
              let from = order.firstIndex(of: dragged),
              let targetIndex = order.firstIndex(of: target)
        else { return order }
        var result = order
        result.remove(at: from)
        guard let newTarget = result.firstIndex(of: target) else { return order }
        let insertAt = from < targetIndex ? newTarget + 1 : newTarget
        result.insert(dragged, at: min(max(insertAt, 0), result.count))
        return result
    }

    /// Reinserisce un nuovo ordine dei SOLI widget visibili dentro l'ordine
    /// completo, lasciando i nascosti nei loro slot. Così il riordino non
    /// perde la posizione di chi è momentaneamente nascosto.
    static func merged(full: [DashboardWidget],
                       visibleOrder: [DashboardWidget],
                       hidden: Set<DashboardWidget>) -> [DashboardWidget] {
        var iterator = visibleOrder.makeIterator()
        return full.map { hidden.contains($0) ? $0 : (iterator.next() ?? $0) }
    }
}
