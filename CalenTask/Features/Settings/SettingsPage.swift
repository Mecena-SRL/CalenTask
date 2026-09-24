import Foundation
import SwiftUI
import Observation

/// Le pagine di Impostazioni. Due famiglie:
/// - **Generali**: come si comporta l'app (avvio, aspetto, notifiche,
///   sincronizzazione, account);
/// - **Moduli**: una panoramica e una pagina per ogni `AppModule`.
///
/// Un solo elenco guida barra laterale (Mac), elenco (iPhone) e ricerca.
/// Nuovo modulo: `case` in `AppModule` (+ le sue `AppFeature`) e le sue
/// opzioni in `ModuleOptions.swift`. Nient'altro da toccare qui.
enum SettingsPage: Hashable, Identifiable {
    case general, appearance, notifications, sync, account
    case modules
    case module(AppModule)

    /// Le pagine generali nella barra laterale (l'account ha la sua testata).
    static let generalPages: [SettingsPage] = [.general, .appearance, .notifications, .sync]

    var id: String {
        switch self {
        case .general: "general"
        case .appearance: "appearance"
        case .notifications: "notifications"
        case .sync: "sync"
        case .account: "account"
        case .modules: "modules"
        case .module(let module): "module.\(module.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .general: "Generale"
        case .appearance: "Aspetto"
        case .notifications: "Notifiche"
        case .sync: "Sincronizzazione"
        case .account: "Account e spazi"
        case .modules: "Panoramica moduli"
        case .module(let module): module.title
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Avvio, finestra, guide e informazioni sull'app."
        case .appearance: "Tema e contenuto della barra laterale."
        case .notifications: "Permesso di sistema e riepilogo del mattino."
        case .sync: "iCloud tra i tuoi dispositivi e calendari di sistema."
        case .account: "Il tuo profilo e gli spazi di lavoro."
        case .modules: "Accendi solo ciò che ti serve: spegnere un modulo nasconde i suoi strumenti ma conserva dati e preferenze."
        case .module(let module): module.detail
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .notifications: "bell.badge"
        case .sync: "arrow.triangle.2.circlepath.icloud"
        case .account: "person.crop.circle"
        case .modules: "square.grid.2x2"
        case .module(let module): module.icon
        }
    }

    var tint: Color {
        switch self {
        case .general: Color(hex: "#8B8D98")
        case .appearance: Color(hex: "#5B5BD6")
        case .notifications: Color(hex: "#E54666")
        case .sync: Color(hex: "#0091FF")
        case .account: Color(hex: "#30A46C")
        case .modules: Color(hex: "#8E4EC6")
        case .module(let module): module.tint
        }
    }

    /// Dove vive l'interruttore di una funzione.
    static func page(for feature: AppFeature) -> SettingsPage {
        switch feature {
        case .sidebarMiniCalendar: .appearance
        case .todayInspector: .general
        default: .module(feature.module)
        }
    }
}

// MARK: Navigazione tra pagine

/// Salto da una pagina all'altra (collegamenti incrociati, panoramica →
/// modulo): su Mac cambia la voce della barra laterale, su iPhone spinge
/// la pagina nello stack. Stesso schema di `AppRouter`.
@Observable @MainActor
final class SettingsRouter {
    var selection: SettingsPage? = .general
    var path: [SettingsPage] = []

    func open(_ page: SettingsPage) {
        #if os(macOS)
        selection = page
        #else
        path.append(page)
        #endif
    }
}

// MARK: Ricerca

/// Le voci cercabili: pagine, funzioni dei moduli e singole preferenze.
struct SettingsSearchEntry: Hashable {
    let title: String
    let page: SettingsPage
    var keywords: [String] = []
}

/// Un risultato per pagina, con le voci che hanno trovato corrispondenza.
struct SettingsSearchResult: Identifiable, Equatable {
    let page: SettingsPage
    let matches: [String]
    var id: String { page.id }
}

enum SettingsSearch {
    static let entries: [SettingsSearchEntry] = {
        var entries: [SettingsSearchEntry] = [
            .init(title: "Schermata iniziale", page: .general, keywords: ["avvio", "apertura", "start"]),
            .init(title: "Guide e suggerimenti", page: .general, keywords: ["benvenuto", "aiuto", "onboarding"]),
            .init(title: "Versione", page: .general, keywords: ["informazioni", "build"]),
            .init(title: "Tema", page: .appearance, keywords: ["chiaro", "scuro", "misto", "colori", "dark"]),
            .init(title: "Sezioni della barra laterale", page: .appearance,
                  keywords: ["sidebar", "preferiti", "progetti", "liste", "etichette"]),
            .init(title: "Permesso notifiche", page: .notifications, keywords: ["avvisi", "promemoria", "alert"]),
            .init(title: "Digest giornaliero", page: .notifications, keywords: ["mattino", "8:00", "riepilogo"]),
            .init(title: "iCloud", page: .sync, keywords: ["cloud", "dispositivi", "mac", "iphone", "backup"]),
            .init(title: "Calendari di sistema", page: .sync,
                  keywords: ["apple", "google", "exchange", "eventkit", "eventi"]),
            .init(title: "Profilo", page: .account, keywords: ["nome", "email", "utente"]),
            .init(title: "Spazi di lavoro", page: .account, keywords: ["workspace", "spazi", "azienda"]),
            .init(title: "Ordine dei moduli", page: .modules, keywords: ["riordina", "ordine"]),
            .init(title: "Configurazione essenziale", page: .modules, keywords: ["ripristina", "reset"]),
            .init(title: "Vista predefinita", page: .module(.calendar), keywords: ["mese", "settimana", "giorno"]),
            .init(title: "Stile del giorno", page: .module(.calendar), keywords: ["agenda", "griglia oraria", "dettaglio"]),
            .init(title: "Stile della settimana", page: .module(.calendar), keywords: ["colonne", "planner", "griglia"]),
            .init(title: "Stile del mese", page: .module(.calendar), keywords: ["elenco", "lista", "griglia"]),
            .init(title: "Giorni della vista settimana", page: .module(.calendar), keywords: ["n giorni"]),
            .init(title: "Trimestre", page: .module(.calendar), keywords: ["tasse", "viste"]),
            .init(title: "Mappa di calore del mese", page: .module(.calendar), keywords: ["heatmap", "densità"]),
            .init(title: "Numeri della settimana", page: .module(.calendar), keywords: ["settimana", "iso"]),
            .init(title: "Orario di lavoro", page: .module(.calendar),
                  keywords: ["ore lavorative", "inizio", "fine", "giornata"]),
            .init(title: "Campi delle card Rapida", page: .module(.activities),
                  keywords: ["scadenza", "priorità", "note", "fase"]),
            .init(title: "Progetti chiusi", page: .module(.projects), keywords: ["archivio", "completati"]),
            .init(title: "Gantt", page: .module(.projects), keywords: ["timeline", "righe"]),
            .init(title: "Team", page: .module(.people), keywords: ["persone", "membri"]),
            .init(title: "Vista per ruolo", page: .module(.people), keywords: ["dashboard", "cruscotto"]),
            .init(title: "Troupe e risorse", page: .module(.production), keywords: ["set", "attrezzatura"]),
        ]
        entries += AppFeature.allCases.map { SettingsSearchEntry(title: $0.title, page: SettingsPage.page(for: $0)) }
        return entries
    }()

    /// Tutte le pagine, per cercare anche per titolo e descrizione.
    static var pages: [SettingsPage] {
        var pages: [SettingsPage] = [.account]
        pages += SettingsPage.generalPages
        pages.append(.modules)
        pages += AppModule.allCases.map { SettingsPage.module($0) }
        return pages
    }

    /// Risultati raggruppati per pagina, nell'ordine delle pagine.
    /// Senza distinzione di maiuscole e accenti.
    static func results(for query: String) -> [SettingsSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return pages.compactMap { page in
            let matches = entries
                .filter { $0.page == page && ([$0.title] + $0.keywords).contains { $0.localizedStandardContains(query) } }
                .map(\.title)
            let pageMatches = page.title.localizedStandardContains(query)
                || page.subtitle.localizedStandardContains(query)
            guard pageMatches || !matches.isEmpty else { return nil }
            return SettingsSearchResult(page: page, matches: matches)
        }
    }
}
