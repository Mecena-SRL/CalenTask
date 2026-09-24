import Foundation
import Observation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case quick, dashboard, inbox, calendar, projects, people

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: "Rapida"
        case .dashboard: "Oggi"
        case .inbox: "Inbox"
        case .calendar: "Calendario"
        case .projects: "Progetti"
        case .people: "Persone"
        }
    }

    var systemImage: String {
        switch self {
        case .quick: "bolt"
        case .dashboard: "sun.max"
        case .inbox: "tray"
        case .calendar: "calendar"
        case .projects: "folder"
        case .people: "person.2"
        }
    }

    /// Variante piena per la sidebar (icone colorate su testo neutro, E11).
    var filledSystemImage: String {
        switch self {
        case .quick: "bolt.fill"
        case .dashboard: "sun.max.fill"
        case .inbox: "tray.fill"
        case .calendar: "calendar"
        case .projects: "folder.fill"
        case .people: "person.2.fill"
        }
    }

    /// Ogni sezione ha la sua personalità cromatica (palette DSPalette).
    var tint: Color {
        switch self {
        case .quick: Color(hex: "#F76B15")      // arancio — l'energia della cattura
        case .dashboard: Color(hex: "#FFB224")  // ambra — il sole di Oggi
        case .inbox: Color(hex: "#12A594")      // smeraldo — la calma del triage
        case .calendar: Color(hex: "#E5484D")   // rosso — il tempo che conta
        case .projects: Color(hex: "#6E56CF")   // viola — la struttura
        case .people: Color(hex: "#3E63DD")     // blu — le persone (CRM, D71)
        }
    }
}

/// La navigazione di primo livello è UNA grammatica per tutte le piattaforme
/// (D70): sezioni, progetti e liste smart sono destinazioni alla pari.
/// Regular (Mac/iPad) le seleziona in sidebar; compact (iPhone) le mappa
/// su tab + push dentro "Sfoglia".
enum AppDestination: Hashable {
    case section(AppSection)
    case project(UUID)
    case smartList(UUID)
    /// F3 — un'etichetta è navigabile come una lista.
    case tag(UUID)
}

@Observable @MainActor
final class AppRouter {
    /// Single instance: the notification delegate needs to reach the router
    /// from outside the SwiftUI environment.
    static let shared = AppRouter()

    /// Ogni finestra parte dalla pagina scelta sul dispositivo.
    var destination: AppDestination

    init() {
        let raw = UserDefaults.standard.string(forKey: AppConfiguration.storageKey) ?? ""
        destination = .section(AppConfiguration.decode(raw).initialSection)
    }

    /// Set by notification deep links; the shell watches it and shows the task detail.
    var taskToOpen: UUID?
    /// F2 — il mini-mese in sidebar porta il Calendario su un giorno preciso.
    var calendarDayToOpen: Date?
    /// F14/F31 — su Mac il dettaglio attività vive nell'inspector a destra.
    var taskForInspector: UUID?
    var isQuickCaptureOpen = false
    /// Modulo "Nuova richiesta" esterna (Intake): vive negli spazi condivisi,
    /// non più nella Inbox (v8). Aperto da dashboard spazio / palette / menu.
    var isIntakeOpen = false
    /// ⌘K (S6/D65).
    var isCommandPaletteOpen = false
    /// Un solo ingresso alle Impostazioni su iOS (D70); macOS usa la scena Settings.
    var isSettingsOpen = false

    func go(_ section: AppSection) {
        destination = .section(section)
    }

    func open(taskID: UUID) {
        taskToOpen = taskID
    }

    func open(projectID: UUID) {
        destination = .project(projectID)
    }

    func open(smartListID: UUID) {
        destination = .smartList(smartListID)
    }

    func open(tagID: UUID) {
        destination = .tag(tagID)
    }

    func open(calendarDay: Date) {
        calendarDayToOpen = calendarDay
        destination = .section(.calendar)
    }

    func inspect(taskID: UUID) {
        taskForInspector = taskID
    }
}
