import Foundation
import os

/// #17 — Log unico dell'app (Console.app → sottosistema `it.mecena.CalenTask`).
/// Prima gli errori finivano in `print` o in `assertionFailure`, che in
/// release non fa nulla: impossibile capire perché un'azione "non va".
nonisolated enum Log {
    static let subsystem = "it.mecena.CalenTask"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let store = Logger(subsystem: subsystem, category: "store")
}

/// Registra l'errore (anche in release) e in debug si ferma come prima.
nonisolated func reportFailure(
    _ message: String, file: StaticString = #fileID, line: UInt = #line
) {
    let location = "\(file):\(line)"
    Log.app.error("\(message, privacy: .public) [\(location, privacy: .public)]")
    assertionFailure(message, file: file, line: line)
}
