import Foundation

/// Decodifica di payload JSON provenienti dalla rete con un tetto alla dimensione,
/// per non allocare risposte anomale (#64).
enum JSONPayload {
    /// 2 MB: ampiamente sopra a release GitHub (30) e meteo (16 giorni).
    static let maxBytes = 2_000_000

    struct TooLarge: Error {}

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= maxBytes else { throw TooLarge() }
        return try JSONDecoder().decode(type, from: data)
    }
}
