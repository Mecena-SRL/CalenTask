import Foundation
import SwiftUI

/// Smart Status (S6/D64): la salute del progetto calcolata, non dichiarata.
/// Rosso = qualcosa è già in ritardo; giallo = si sta stringendo
/// (scadenze entro 3 giorni o troppe bloccate); verde = respira.
enum ProjectSmartStatus: String {
    case onTrack, atRisk, late

    var label: String {
        switch self {
        case .onTrack: "In carreggiata"
        case .atRisk: "Sotto pressione"
        case .late: "In ritardo"
        }
    }

    var color: Color {
        switch self {
        case .onTrack: Color(hex: "#30A46C")
        case .atRisk: Color(hex: "#FFB224")
        case .late: Color(hex: "#E5484D")
        }
    }
}

extension Project {
    var smartStatus: ProjectSmartStatus {
        let open = tasks.filter { $0.deletedAt == nil && !$0.isDone && !$0.isTemplate }
        guard !open.isEmpty else { return .onTrack }
        let today = Calendar.current.startOfDay(for: .now)

        if open.contains(where: { ($0.dueAt ?? .distantFuture) < today }) {
            return .late
        }
        let soon = Calendar.current.date(byAdding: .day, value: 3, to: today) ?? today
        let dueSoon = open.filter { ($0.dueAt ?? .distantFuture) < soon }.count
        let blocked = open.filter { $0.status == .blocked }.count
        if dueSoon >= 3 || Double(blocked) / Double(open.count) > 0.3 {
            return .atRisk
        }
        return .onTrack
    }
}
