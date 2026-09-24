import SwiftUI

/// Semantic typography on top of Dynamic Type.
extension Font {
    static let dsScreenTitle = Font.largeTitle.bold()
    static let dsSectionTitle = Font.title3.weight(.semibold)
    static let dsRowTitle = Font.headline
    static let dsMeta = Font.subheadline
    static let dsCaption = Font.caption
    /// Dates and counters align vertically with monospaced digits.
    static let dsNumeric = Font.subheadline.monospacedDigit()
    static let dsStatNumber = Font.system(.title, design: .rounded).weight(.bold).monospacedDigit()
}
