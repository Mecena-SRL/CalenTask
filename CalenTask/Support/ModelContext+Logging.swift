import Foundation
import os
import SwiftData

/// #17 — Salvataggi e letture che non ingoiano l'errore. Con `try?` un
/// salvataggio o una fetch falliti sparivano senza traccia (l'azione "non
/// va" e basta); qui l'errore finisce nel log `store` (Console.app) e il
/// chiamante riceve un valore neutro, semplice come prima.
extension ModelContext {
    /// Salva; se fallisce registra l'errore e ritorna `false`.
    @discardableResult
    nonisolated func saveOrLog(file: StaticString = #fileID, line: UInt = #line) -> Bool {
        do {
            try save()
            return true
        } catch {
            let location = "\(file):\(line)"
            Log.store.error(
                "Salvataggio fallito: \(String(describing: error), privacy: .public) [\(location, privacy: .public)]"
            )
            return false
        }
    }

    /// Esegue la fetch; se fallisce registra l'errore e ritorna `[]`.
    nonisolated func fetchOrLog<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>, file: StaticString = #fileID, line: UInt = #line
    ) -> [T] {
        do {
            return try fetch(descriptor)
        } catch {
            let location = "\(file):\(line)"
            Log.store.error(
                "Lettura di \(String(describing: T.self), privacy: .public) fallita: \(String(describing: error), privacy: .public) [\(location, privacy: .public)]"
            )
            return []
        }
    }
}
