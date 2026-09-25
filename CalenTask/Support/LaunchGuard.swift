import Foundation

/// Avvio sicuro: se l'avvio precedente non è arrivato a regime (crash o
/// blocco nei primi secondi), questa sessione parte con l'essenziale —
/// niente stato della finestra salvato (es. tutto schermo), niente pannello
/// destro né mini-calendario, pagina Oggi — e lo dice. Così l'app si apre
/// comunque, e si capisce se il problema sta in quelle parti.
///
/// Solo su Mac: su iOS il sistema chiude le app in background senza
/// avvisare, e il segnale "avvio non finito" sarebbe falso.
enum LaunchGuard {
    private static let inProgressKey = "launch.inProgress"
    /// Impostazioni › Sviluppatore: forza l'avvio sicuro alla prossima apertura.
    static let forceSafeModeKey = "launch.forceSafeMode"

    /// Deciso una volta, al primo accesso (da `CalenTaskApp.init`, prima che
    /// le finestre vengano create o ripristinate).
    static let isSafeMode: Bool = {
        #if os(macOS)
        let defaults = UserDefaults.standard
        let previousDidNotFinish = defaults.bool(forKey: inProgressKey)
        let forced = defaults.bool(forKey: forceSafeModeKey)
        defaults.set(true, forKey: inProgressKey)
        defaults.set(false, forKey: forceSafeModeKey)
        let safe = previousDidNotFinish || forced
        if safe { resetWindowState() }
        return safe
        #else
        return false
        #endif
    }()

    /// L'app è arrivata a regime (o si chiude normalmente).
    static func markLaunchCompleted() {
        UserDefaults.standard.set(false, forKey: inProgressKey)
    }

    /// Dimentica finestra, colonne e barra strumenti salvate (e il ripristino
    /// delle finestre, compreso il tutto schermo): si riparte dal default.
    static func resetWindowState() {
        let defaults = UserDefaults.standard
        let prefixes = ["NSWindow Frame", "NSSplitView Subview Frames", "NSToolbar Configuration",
                        "NSNavPanel", "NSTableView"]
        for key in defaults.dictionaryRepresentation().keys
        where prefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.removeObject(forKey: key)
        }
        #if os(macOS)
        if let bundleID = Bundle.main.bundleIdentifier,
           let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let saved = library.appendingPathComponent("Saved Application State/\(bundleID).savedState")
            try? FileManager.default.removeItem(at: saved)
        }
        #endif
    }
}
