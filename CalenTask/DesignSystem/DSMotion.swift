import SwiftUI

/// E5 — Due spring di sistema, niente easeInOut/duration.
/// `dsQuick` per le interazioni dirette (toggle, hover, chip),
/// `dsSoft` per i cambi di layout (collasso righe, sezioni).
extension Animation {
    static let dsQuick = Animation.spring(response: 0.30, dampingFraction: 0.80)
    static let dsSoft = Animation.spring(response: 0.45, dampingFraction: 0.75)
}
