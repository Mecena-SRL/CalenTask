import SwiftUI

/// E1 — Quattro livelli di elevazione: canvas → card → panel → modal.
/// Ricetta Linear: superficie + bordo hairline 1px + ombra ambientale morbida.
/// In dark la superficie si schiarisce col livello (derivazione percettiva),
/// in light resta bianca e parla l'ombra.
enum DSElevation: Int {
    case canvas = 0
    case card = 1
    case panel = 2
    case modal = 3

    var surface: Color {
        switch self {
        case .canvas:
            Color(light: Color(.sRGB, red: 0.97, green: 0.97, blue: 0.98),
                  dark: Color(.sRGB, red: 0.09, green: 0.10, blue: 0.11))
        case .card:
            Color(light: Color(white: 1.0),
                  dark: Color(.sRGB, red: 0.13, green: 0.14, blue: 0.15))
        case .panel:
            Color(light: Color(white: 1.0),
                  dark: Color(.sRGB, red: 0.16, green: 0.17, blue: 0.18))
        case .modal:
            Color(light: Color(white: 1.0),
                  dark: Color(.sRGB, red: 0.19, green: 0.20, blue: 0.21))
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .canvas: 0
        case .card: 10
        case .panel: 14
        case .modal: 18
        }
    }

    var shadowY: CGFloat { self == .canvas ? 0 : 3 }
}

extension DSColor {
    /// Bordo hairline delle superfici elevate (light: nero 6%, dark: bianco 8%).
    static let hairline = Color(
        light: Color.black.opacity(0.06),
        dark: Color.white.opacity(0.08)
    )
    /// Hairline rinforzata per hover/selezione (E9).
    static let hairlineStrong = Color(
        light: Color.black.opacity(0.12),
        dark: Color.white.opacity(0.16)
    )
    /// Ombra ambientale unica (0.05 light / 0.25 dark).
    static let ambientShadow = Color(
        light: Color.black.opacity(0.05),
        dark: Color.black.opacity(0.25)
    )
}

private struct DSSurfaceModifier: ViewModifier {
    let level: DSElevation
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(level.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(DSColor.hairline)
            }
            .shadow(color: DSColor.ambientShadow,
                    radius: level.shadowRadius, y: level.shadowY)
    }
}

/// E9 — feedback hover nei token (solo macOS): velo leggero + hairline
/// rinforzata. Su iOS è un no-op.
private struct DSHoverHighlightModifier: ViewModifier {
    var cornerRadius: CGFloat
    @State private var isHovering = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .background(
                Color.primary.opacity(isHovering ? 0.05 : 0),
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
            .onHover { hovering in
                withAnimation(.dsQuick) { isHovering = hovering }
            }
        #else
        content
        #endif
    }
}

extension View {
    /// Applica superficie + hairline + ombra ambientale del livello dato (E1).
    func dsSurface(_ level: DSElevation,
                   cornerRadius: CGFloat = DS.Radius.medium) -> some View {
        modifier(DSSurfaceModifier(level: level, cornerRadius: cornerRadius))
    }

    /// Evidenzia al passaggio del mouse su macOS (E9).
    func dsHoverHighlight(cornerRadius: CGFloat = DS.Radius.small) -> some View {
        modifier(DSHoverHighlightModifier(cornerRadius: cornerRadius))
    }
}
