import SwiftUI

/// Tema dell'app: automatico (segue il sistema), chiaro, scuro, oppure
/// misto — sidebar e chrome scuri con contenuto chiaro (solo macOS).
enum DSAppearance: String, CaseIterable, Identifiable {
    case auto, light, dark, mixed

    static let storageKey = "appAppearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Automatico"
        case .light: "Chiaro"
        case .dark: "Scuro"
        case .mixed: "Misto"
        }
    }

    var systemImage: String {
        switch self {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        case .mixed: "rectangle.leadinghalf.inset.filled"
        }
    }

    /// Schema forzato sull'intera finestra (auto e misto seguono il sistema).
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .auto, .mixed: nil
        }
    }

    /// Le opzioni proposte sulla piattaforma corrente (misto è solo macOS).
    static var available: [DSAppearance] {
        #if os(macOS)
        allCases
        #else
        [.auto, .light, .dark]
        #endif
    }
}

/// Tema misto (D47): forza lo schema scuro su una sotto-gerarchia
/// (la sidebar) lasciando il resto al sistema.
struct DSMixedSchemeModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.environment(\.colorScheme, .dark)
        } else {
            content
        }
    }
}
