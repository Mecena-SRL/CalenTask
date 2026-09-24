import Foundation
import SwiftData

/// Una scena dello stripboard (D54): striscia INT/EST · giorno/notte,
/// assegnabile a un giorno di ripresa. "ProductionScene" perché `Scene`
/// collide con SwiftUI.Scene. Tabella Supabase `scenes`.
@Model
final class ProductionScene {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var projectID: UUID = UUID()
    /// Numero di scena come in sceneggiatura ("12", "12A").
    var number: String = ""
    /// La slugline / sinossi breve della scena.
    var slug: String = ""
    var intExtRaw: String = ""
    var dayNightRaw: String = ""
    var locationName: String = ""
    /// Lunghezza in ottavi di pagina (convenzione di produzione).
    var pageEighths: Int = 0
    /// Cast e figure chiave, per la call sheet.
    var castNames: [String] = []
    /// Il giorno di ripresa assegnato (TodoTask kind .shootDay); nil = da pianificare.
    var shootDayID: UUID?
    var statusRaw: String = ""
    var sortOrder: Int = 0
    var notes: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var intExt: SceneIntExt {
        get { SceneIntExt(rawValue: intExtRaw) ?? .int }
        set { intExtRaw = newValue.rawValue }
    }

    var dayNight: SceneDayNight {
        get { SceneDayNight(rawValue: dayNightRaw) ?? .day }
        set { dayNightRaw = newValue.rawValue }
    }

    var status: SceneStatus {
        get { SceneStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    /// Etichetta pagine in ottavi: "1 2/8".
    var pagesLabel: String {
        let whole = pageEighths / 8
        let eighths = pageEighths % 8
        switch (whole, eighths) {
        case (0, 0): return "—"
        case (_, 0): return "\(whole)"
        case (0, _): return "\(eighths)/8"
        default: return "\(whole) \(eighths)/8"
        }
    }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        projectID: UUID,
        number: String,
        slug: String = "",
        intExt: SceneIntExt = .int,
        dayNight: SceneDayNight = .day,
        locationName: String = "",
        pageEighths: Int = 0,
        sortOrder: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.projectID = projectID
        self.number = number
        self.slug = slug
        self.intExtRaw = intExt.rawValue
        self.dayNightRaw = dayNight.rawValue
        self.locationName = locationName
        self.pageEighths = pageEighths
        self.statusRaw = SceneStatus.planned.rawValue
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

// MARK: - Enums di scena

enum SceneIntExt: String, Codable, CaseIterable, Identifiable {
    case int, ext, intExt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .int: "INT"
        case .ext: "EST"
        case .intExt: "INT/EST"
        }
    }
}

enum SceneDayNight: String, Codable, CaseIterable, Identifiable {
    case day, night, dawn, dusk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: "Giorno"
        case .night: "Notte"
        case .dawn: "Alba"
        case .dusk: "Tramonto"
        }
    }

    var shortLabel: String {
        switch self {
        case .day: "G"
        case .night: "N"
        case .dawn: "A"
        case .dusk: "T"
        }
    }
}

enum SceneStatus: String, Codable, CaseIterable, Identifiable {
    case planned, shot, omitted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .planned: "Da girare"
        case .shot: "Girata"
        case .omitted: "Omessa"
        }
    }
}
