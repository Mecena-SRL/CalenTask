import SwiftUI

extension Color {
    /// Cross-platform dynamic color (light/dark) without asset catalog entries.
    init(light: Color, dark: Color) {
        #if os(macOS)
        self = Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
        #else
        self = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #endif
    }

    /// Parses "#RRGGBB" / "RRGGBB" (used by Project.colorHex and Tag.colorHex).
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Color tokens. Accent comes from the asset catalog (petrol teal #0E7490).
enum DSColor {
    static let surface = Color(
        light: Color(white: 1.0),
        dark: Color(.sRGB, red: 0.11, green: 0.12, blue: 0.13)
    )
    static let surfaceSecondary = Color(
        light: Color(.sRGB, red: 0.96, green: 0.96, blue: 0.97),
        dark: Color(.sRGB, red: 0.16, green: 0.17, blue: 0.18)
    )
    static let overdue = Color(
        light: Color(.sRGB, red: 0.86, green: 0.15, blue: 0.15),
        dark: Color(.sRGB, red: 0.97, green: 0.44, blue: 0.44)
    )

    static func status(_ status: TaskStatus) -> Color {
        switch status {
        case .todo: Color(light: Color(.sRGB, red: 0.55, green: 0.58, blue: 0.62),
                          dark: Color(.sRGB, red: 0.58, green: 0.62, blue: 0.66))
        case .doing: Color(light: Color(.sRGB, red: 0.15, green: 0.45, blue: 0.85),
                           dark: Color(.sRGB, red: 0.38, green: 0.62, blue: 0.96))
        case .blocked: Color(light: Color(.sRGB, red: 0.92, green: 0.55, blue: 0.10),
                             dark: Color(.sRGB, red: 0.98, green: 0.66, blue: 0.28))
        case .done: Color(light: Color(.sRGB, red: 0.13, green: 0.65, blue: 0.37),
                          dark: Color(.sRGB, red: 0.29, green: 0.78, blue: 0.50))
        }
    }

    static func priority(_ priority: TaskPriority) -> Color {
        switch priority {
        case .low: Color(light: Color(.sRGB, red: 0.62, green: 0.65, blue: 0.69),
                         dark: Color(.sRGB, red: 0.55, green: 0.58, blue: 0.62))
        case .normal: Color.accentColor
        case .high: Color(light: Color(.sRGB, red: 0.92, green: 0.55, blue: 0.10),
                          dark: Color(.sRGB, red: 0.98, green: 0.66, blue: 0.28))
        case .urgent: overdue
        }
    }
}
