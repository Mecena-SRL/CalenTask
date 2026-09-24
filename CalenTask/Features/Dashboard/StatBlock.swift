import SwiftUI

/// I quattro indicatori in cima alla dashboard "Oggi". Sono il primo
/// mattone del cruscotto a widget personalizzabile (D93): ognuno ha una
/// visibilità propria, ricordata tra i lanci.
enum StatBlock: String, CaseIterable, Identifiable {
    case overdue
    case today
    case week
    case inbox

    var id: String { rawValue }

    /// Chiave @AppStorage della visibilità scelta dall'utente.
    var storageKey: String { "dashboard.statBlock.\(rawValue)" }

    var title: String {
        switch self {
        case .overdue: "In ritardo"
        case .today: "Oggi"
        case .week: "Settimana"
        case .inbox: "Inbox"
        }
    }

    var icon: String {
        switch self {
        case .overdue: "exclamationmark.circle"
        case .today: "sun.max"
        case .week: "calendar"
        case .inbox: "tray"
        }
    }

    /// Default ragionato: gli indicatori "rumorosi a zero" (arretrati e
    /// inbox) compaiono solo quando contano qualcosa; oggi e settimana
    /// restano sempre, sono il battito del cruscotto.
    var defaultVisibility: BlockVisibility {
        switch self {
        case .overdue, .inbox: .autoHide
        case .today, .week: .always
        }
    }
}

/// Come si comporta un blocco del cruscotto: sempre, mai, o solo se ha
/// qualcosa da dire.
enum BlockVisibility: String, CaseIterable, Identifiable {
    case always
    case autoHide
    case hidden

    var id: String { rawValue }

    var label: String {
        switch self {
        case .always: "Mostra sempre"
        case .autoHide: "Nascondi se vuoto"
        case .hidden: "Nascondi"
        }
    }

    var systemImage: String {
        switch self {
        case .always: "eye"
        case .autoHide: "eye.trianglebadge.exclamationmark"
        case .hidden: "eye.slash"
        }
    }

    /// Decide se il blocco va mostrato dato il suo valore corrente.
    func shouldShow(count: Int) -> Bool {
        switch self {
        case .always: true
        case .autoHide: count > 0
        case .hidden: false
        }
    }
}
