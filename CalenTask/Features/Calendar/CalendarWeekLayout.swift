import Foundation

/// La disposizione di una riga di giorni consecutivi (una settimana del Mese,
/// la fascia "tutto il giorno" della Settimana): ogni elemento occupa un
/// intervallo di colonne su una **corsia**.
///
/// - Gli eventi su più giorni diventano **barre continue** (non più una copia
///   per giorno).
/// - Le corsie si assegnano dal più lungo al più corto, poi per inizio (come
///   i calendari di Apple e Google): le barre lunghe restano in alto, intere.
/// - Con poche corsie visibili, l'ultima diventa "+N" dove non ci sta tutto.
///
/// Logica pura, senza SwiftUI: testata in `CalendarWeekLayoutTests`.
struct CalendarWeekLayout: Equatable {
    struct Segment: Equatable {
        enum Kind: Equatable {
            /// Evento su più giorni o "tutto il giorno": barra piena.
            case span
            /// Evento/attività con orario in un solo giorno.
            case timed
            /// La scadenza di un'attività.
            case due
        }

        let id: UUID
        /// Prima e ultima colonna occupata (0-based, incluse).
        let start: Int
        let end: Int
        var kind: Kind = .timed
        /// A parità di lunghezza e colonna: l'orario, per l'ordine della giornata.
        var sortKey: Date = .distantPast
        /// L'elemento inizia prima / finisce dopo la riga (barra "tagliata").
        var continuesBefore = false
        var continuesAfter = false

        var length: Int { end - start + 1 }
    }

    struct Placement: Equatable, Identifiable {
        let segment: Segment
        let lane: Int
        var id: String { "\(segment.id.uuidString)-\(segment.kind)-\(segment.start)" }

        func covers(_ column: Int) -> Bool { segment.start <= column && column <= segment.end }
    }

    let columns: Int
    let placements: [Placement]

    init(columns: Int, segments: [Segment]) {
        self.columns = max(columns, 0)
        let columnCount = self.columns
        let ordered = segments
            .map { segment in
                Segment(id: segment.id, start: max(segment.start, 0), end: min(segment.end, columnCount - 1),
                        kind: segment.kind, sortKey: segment.sortKey,
                        continuesBefore: segment.continuesBefore, continuesAfter: segment.continuesAfter)
            }
            .filter { $0.start <= $0.end }
            .sorted { a, b in
                if a.length != b.length { return a.length > b.length }
                if a.start != b.start { return a.start < b.start }
                if a.sortKey != b.sortKey { return a.sortKey < b.sortKey }
                return a.id.uuidString < b.id.uuidString
            }

        var occupied: [[Bool]] = []
        var result: [Placement] = []
        for segment in ordered {
            let range = segment.start...segment.end
            var lane = 0
            while lane < occupied.count, range.contains(where: { occupied[lane][$0] }) {
                lane += 1
            }
            if lane == occupied.count {
                occupied.append(Array(repeating: false, count: columnCount))
            }
            for column in range { occupied[lane][column] = true }
            result.append(Placement(segment: segment, lane: lane))
        }
        placements = result
    }

    /// Le corsie usate dalla riga.
    var laneCount: Int { (placements.map(\.lane).max() ?? -1) + 1 }

    /// Le corsie che servono a una colonna (la più alta occupata + 1).
    func lanesUsed(column: Int) -> Int {
        (placements.filter { $0.covers(column) }.map(\.lane).max() ?? -1) + 1
    }

    /// Le colonne che non stanno in `maxLanes` corsie.
    func overflowingColumns(maxLanes: Int) -> Set<Int> {
        Set((0..<columns).filter { lanesUsed(column: $0) > maxLanes })
    }

    /// Ciò che si vede con `maxLanes` corsie: tutto sotto l'ultima corsia;
    /// nell'ultima solo ciò che non attraversa colonne che traboccano (lì
    /// l'ultima corsia è il "+N").
    func visiblePlacements(maxLanes: Int) -> [Placement] {
        guard maxLanes > 0 else { return [] }
        let overflowing = overflowingColumns(maxLanes: maxLanes)
        return placements.filter { placement in
            if placement.lane < maxLanes - 1 { return true }
            if placement.lane > maxLanes - 1 { return false }
            return !(placement.segment.start...placement.segment.end).contains { overflowing.contains($0) }
        }
    }

    /// Per ogni colonna, quanti elementi restano nascosti (il numero del "+N").
    func hiddenCounts(maxLanes: Int) -> [Int] {
        let visible = Set(visiblePlacements(maxLanes: maxLanes).map(\.id))
        return (0..<columns).map { column in
            placements.filter { $0.covers(column) && !visible.contains($0.id) }.count
        }
    }
}

extension CalendarWeekLayout {
    /// I segmenti di una riga di giorni consecutivi (`days`): l'intervallo
    /// inizio→fine (anche su più giorni, fine esclusiva a mezzanotte) e, se la
    /// scadenza cade fuori da quell'intervallo, un segnaposto sul suo giorno.
    static func segments(for tasks: [TodoTask], days: [Date], calendar: Calendar) -> [Segment] {
        guard let first = days.first, let last = days.last else { return [] }
        let firstDay = calendar.startOfDay(for: first)
        let lastDay = calendar.startOfDay(for: last)
        func column(of day: Date) -> Int {
            calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: day)).day ?? 0
        }

        var result: [Segment] = []
        var seen = Set<UUID>()
        for task in tasks where seen.insert(task.id).inserted {
            var span: ClosedRange<Date>?
            if let startAt = task.startAt {
                let spanStart = calendar.startOfDay(for: startAt)
                var spanEnd = spanStart
                if let endAt = task.endAt, endAt > startAt {
                    spanEnd = max(spanStart, calendar.startOfDay(for: endAt.addingTimeInterval(-1)))
                }
                span = spanStart...spanEnd
                if spanEnd >= firstDay && spanStart <= lastDay {
                    result.append(Segment(
                        id: task.id,
                        start: column(of: spanStart),
                        end: column(of: spanEnd),
                        kind: spanEnd > spanStart || task.allDay ? .span : .timed,
                        sortKey: startAt,
                        continuesBefore: spanStart < firstDay,
                        continuesAfter: spanEnd > lastDay
                    ))
                }
            }
            if let dueAt = task.dueAt {
                let dueDay = calendar.startOfDay(for: dueAt)
                let insideSpan = span?.contains(dueDay) ?? false
                if !insideSpan && dueDay >= firstDay && dueDay <= lastDay {
                    let dueColumn = column(of: dueDay)
                    result.append(Segment(id: task.id, start: dueColumn, end: dueColumn, kind: .due, sortKey: dueAt))
                }
            }
        }
        return result
    }

    /// Le attività (senza doppioni) che toccano una riga di giorni, dall'indice
    /// per giorno del calendario.
    static func tasks(in days: [Date], from tasksByDay: [Date: [TodoTask]], calendar: Calendar) -> [TodoTask] {
        var seen = Set<UUID>()
        return days.flatMap { tasksByDay[calendar.startOfDay(for: $0)] ?? [] }
            .filter { seen.insert($0.id).inserted }
    }
}
