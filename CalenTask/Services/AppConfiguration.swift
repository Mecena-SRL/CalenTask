import Foundation
import SwiftUI

/// Preferenze di presentazione del dispositivo. Nascondere un modulo non
/// modifica i dati e non concede né revoca permessi su uno spazio.
struct AppConfiguration: Codable, Equatable {
    static let storageKey = "app.configuration.v1"

    // Raw strings keep preferences from newer app versions intact.
    private var modules: Set<String> = [AppModule.activities.rawValue]
    private var features: Set<String> = [AppFeature.calendarWeather.rawValue]
    var startPage: AppStartPage = .calendar
    /// Ordine scelto in Impostazioni (barra laterale dei moduli): guida sia
    /// l'elenco lì sia l'ordine delle sezioni nella sidebar principale
    /// dell'app. Vuoto finché non si riordina mai nulla.
    private var moduleOrderRaw: [String] = []

    static let standard = AppConfiguration()

    static func decode(_ raw: String) -> Self {
        guard let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data)
        else { return .standard }
        return value
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func isEnabled(_ module: AppModule) -> Bool {
        if module == .calendar { return true }
        if module == .production && !isEnabled(.projects) { return false }
        return modules.contains(module.rawValue)
    }

    func isEnabled(_ feature: AppFeature) -> Bool {
        isEnabled(feature.module) && features.contains(feature.rawValue)
    }

    mutating func set(_ module: AppModule, enabled: Bool) {
        guard module != .calendar else { return }
        if enabled { modules.insert(module.rawValue) }
        else { modules.remove(module.rawValue) }
    }

    mutating func set(_ feature: AppFeature, enabled: Bool) {
        if enabled { features.insert(feature.rawValue) }
        else { features.remove(feature.rawValue) }
    }

    /// I moduli nell'ordine scelto — Calendario sempre primo (è l'unico
    /// "sempre attivo", non ha senso spostarlo). Completato con eventuali
    /// moduli nuovi (in coda) e ripulito da raw sconosciuti, come
    /// `DashboardLayout.order(from:)`.
    var moduleOrder: [AppModule] {
        get {
            var seen = Set<AppModule>()
            var result = moduleOrderRaw
                .compactMap(AppModule.init(rawValue:))
                .filter { seen.insert($0).inserted }
            for module in AppModule.allCases where !result.contains(module) {
                result.append(module)
            }
            if let index = result.firstIndex(of: .calendar), index != 0 {
                result.remove(at: index)
                result.insert(.calendar, at: 0)
            }
            return result
        }
        set {
            var order = newValue.filter { $0 != .calendar }
            order.insert(.calendar, at: 0)
            moduleOrderRaw = order.map(\.rawValue)
        }
    }

    var navigationSections: [AppSection] {
        var sections: [AppSection] = [.calendar, .dashboard]
        for module in moduleOrder where module != .calendar && isEnabled(module) {
            sections += module.sidebarSections
        }
        return sections
    }

    var initialSection: AppSection {
        switch startPage {
        case .calendar: .calendar
        case .today: .dashboard
        case .quick: isEnabled(.activities) ? .quick : .calendar
        }
    }
}

enum AppStartPage: String, Codable, CaseIterable, Identifiable {
    case calendar, today, quick
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calendar: "Calendario"
        case .today: "Oggi"
        case .quick: "Rapida"
        }
    }
}

enum AppModule: String, CaseIterable, Identifiable {
    case calendar, activities, projects, people, insights, production
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calendar: "Calendario"
        case .activities: "Attività"
        case .projects: "Progetti"
        case .people: "Persone"
        case .insights: "Analisi"
        case .production: "Produzione"
        }
    }
    var icon: String {
        switch self {
        case .calendar: "calendar"
        case .activities: "checklist"
        case .projects: "folder"
        case .people: "person.2"
        case .insights: "chart.xyaxis.line"
        case .production: "movieclapper"
        }
    }
    var detail: String {
        switch self {
        case .calendar: "Giorno, settimana e mese, sempre disponibili."
        case .activities: "Cattura rapida, Inbox e organizzazione delle attività."
        case .projects: "Progetti, fasi e widget di pianificazione."
        case .people: "Contatti e assegnatari locali. La collaborazione online non è ancora disponibile."
        case .insights: "Suggerimenti, andamento e carico di lavoro nei widget di Oggi."
        case .production: "Troupe, spoglio e piani di ripresa. Richiede Progetti."
        }
    }

    /// Personalità cromatica del modulo (badge stile Impostazioni di Sistema,
    /// coerente con `AppSection.tint` dove i due si sovrappongono).
    var tint: Color {
        switch self {
        case .calendar: Color(hex: "#E5484D")    // rosso — come AppSection.calendar
        case .activities: Color(hex: "#F76B15")  // arancio — come AppSection.quick
        case .projects: Color(hex: "#6E56CF")    // viola — come AppSection.projects
        case .people: Color(hex: "#3E63DD")      // blu — come AppSection.people
        case .insights: Color(hex: "#00A2C7")    // ciano — analisi
        case .production: Color(hex: "#AD7F58")  // bronzo — troupe e set
        }
    }

    /// A cosa corrisponde questo modulo nella sidebar principale — Analisi e
    /// Produzione non hanno una sezione propria (vivono nei widget di Oggi e
    /// nel dettaglio progetto), quindi riordinarli non sposta nulla lì.
    var sidebarSections: [AppSection] {
        switch self {
        case .calendar: [.calendar]
        case .activities: [.quick, .inbox]
        case .projects: [.projects]
        case .people: [.people]
        case .insights, .production: []
        }
    }
}

enum AppFeature: String, CaseIterable, Identifiable {
    case calendarAdvancedViews, calendarWeather, calendarSummary, calendarUnscheduled
    case sidebarMiniCalendar, todayInspector, smartLists, tags, externalRequests, dashboardMetrics
    var id: String { rawValue }
    var module: AppModule {
        switch self {
        case .calendarAdvancedViews, .calendarWeather, .calendarSummary,
             .calendarUnscheduled, .sidebarMiniCalendar, .todayInspector: .calendar
        case .smartLists, .tags: .activities
        case .externalRequests: .people
        case .dashboardMetrics: .insights
        }
    }
    var title: String {
        switch self {
        case .calendarAdvancedViews: "Viste calendario aggiuntive"
        case .calendarWeather: "Meteo"
        case .calendarSummary: "Riepiloghi e disponibilità"
        case .calendarUnscheduled: "Attività da pianificare"
        case .sidebarMiniCalendar: "Mini calendario nella barra laterale"
        case .todayInspector: "Pannello Oggi nelle finestre ampie"
        case .smartLists: "Liste smart"
        case .tags: "Etichette"
        case .externalRequests: "Registrazione richieste esterne"
        case .dashboardMetrics: "Indicatori numerici in Oggi"
        }
    }
}
