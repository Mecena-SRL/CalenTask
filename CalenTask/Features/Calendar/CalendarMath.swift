import Foundation

// L'app è in italiano a prescindere dalla lingua del dispositivo: le date
// vanno formattate in italiano e la settimana inizia di lunedì.
extension Locale {
    static let app = Locale(identifier: "it_IT")
}

extension Calendar {
    /// Calendario italiano: settimana da lunedì, simboli dei giorni in italiano.
    static let app: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .app
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        return calendar
    }()
}

extension Date {
    /// Formattazione con locale italiano (nomi di giorno/mese coerenti con la UI).
    func appFormatted(_ style: Date.FormatStyle) -> String {
        formatted(style.locale(.app))
    }
}

extension Comparable {
    /// Riporta il valore dentro `range` (clamp). Usato per la densità oraria.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Pure month-grid helpers (unit-tested, no UI dependencies).
enum CalendarMath {
    /// 6 weeks × 7 days covering the month of `month`, aligned to the
    /// calendar's locale-aware first weekday (Monday in it_IT).
    static func monthGrid(for month: Date, calendar: Calendar) -> [[Date]] {
        let firstOfMonth = startOfMonth(for: month, calendar: calendar)
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: firstOfMonth) else {
            return []
        }
        return (0..<6).map { week in
            (0..<7).compactMap { day in
                calendar.date(byAdding: .day, value: week * 7 + day, to: gridStart)
            }
        }
    }

    static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Weekday symbols reordered so they start at the calendar's first weekday.
    static func orderedWeekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    static func isSameMonth(_ a: Date, _ b: Date, calendar: Calendar) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }

    // MARK: Sovrapposizioni → colonne (condiviso da Griglia e Gantt verticale)

    /// La fine "effettiva" di un blocco: almeno 30' così due eventi attaccati
    /// non si schiacciano a zero quando si calcolano le colonne.
    private static func effectiveEnd(_ task: TodoTask) -> Date {
        guard let startAt = task.startAt else { return .distantPast }
        let end = task.endAt ?? startAt.addingTimeInterval(3600)
        return max(end, startAt.addingTimeInterval(30 * 60))
    }

    /// Ordina gli eventi per inizio (poi per fine effettiva): l'ordine in cui si
    /// impilano nella cascata (0 = sotto, ultimo = sopra).
    private static func sortedForLayout(_ tasks: [TodoTask]) -> [TodoTask] {
        tasks.filter { $0.startAt != nil && !$0.allDay }.sorted { a, b in
            let sa = a.startAt ?? .distantPast
            let sb = b.startAt ?? .distantPast
            if sa != sb { return sa < sb }
            let ea = effectiveEnd(a), eb = effectiveEnd(b)
            if ea != eb { return ea < eb }
            // Query order can change after sync. Equal intervals must keep
            // the same cascade order (and foreground card) across renders.
            return a.id.uuidString < b.id.uuidString
        }
    }

    /// Gli eventi raggruppati per **cluster di sovrapposizione** (transitiva):
    /// ogni cluster è ordinato per inizio, così l'indice nell'array è la
    /// "profondità" della carta nella cascata.
    static func overlapClusters(for tasks: [TodoTask]) -> [[TodoTask]] {
        var clusters: [[TodoTask]] = []
        var cluster: [TodoTask] = []
        var clusterEnd: Date = .distantPast
        for task in sortedForLayout(tasks) {
            let start = task.startAt ?? .distantPast
            if cluster.isEmpty || start < clusterEnd {
                cluster.append(task)
                clusterEnd = max(clusterEnd, effectiveEnd(task))
            } else {
                clusters.append(cluster)
                cluster = [task]
                clusterEnd = effectiveEnd(task)
            }
        }
        if !cluster.isEmpty { clusters.append(cluster) }
        return clusters
    }

    /// La carta "attiva" di un cluster: quella **sotto il cursore** (hover),
    /// altrimenti quella **scelta col tap**, altrimenti `nil` — e a riposo
    /// (nessuna attiva) in cima resta l'ultima, cioè l'ordine gerarchico.
    /// Restituire solo l'attiva (non il default) serve a distinguere la carta
    /// **sollevata** (che anima) da quella semplicemente in cima a riposo.
    static func activeCascadeID(
        in cluster: [TodoTask], hovered: UUID?, tapped: UUID?
    ) -> UUID? {
        if let hovered, cluster.contains(where: { $0.id == hovered }) { return hovered }
        if let tapped, cluster.contains(where: { $0.id == tapped }) { return tapped }
        return nil
    }

    /// Sfalsamento orizzontale di una carta nella cascata: un passo per
    /// profondità (proporzionale alla corsia, ma limitato), con un tetto così la
    /// carta in primo piano resta sempre abbondantemente leggibile.
    static func cascadeInset(depth: Int, laneWidth: CGFloat) -> CGFloat {
        guard depth > 0 else { return 0 }
        let step = min(24, max(12, laneWidth * 0.16))
        return min(CGFloat(depth) * step, laneWidth * 0.55)
    }

    /// Per ogni evento: profondità nella cascata, dimensione del cluster e
    /// indice del cluster. Usato da Giorno e Settimana per impilare le
    /// sovrapposizioni come carte sfalsate invece che a colonne strette.
    static func cascadeLayout(
        for tasks: [TodoTask]
    ) -> [UUID: (depth: Int, count: Int, cluster: Int)] {
        var map: [UUID: (depth: Int, count: Int, cluster: Int)] = [:]
        for (clusterIndex, cluster) in overlapClusters(for: tasks).enumerated() {
            for (depth, task) in cluster.enumerated() {
                map[task.id] = (depth, cluster.count, clusterIndex)
            }
        }
        return map
    }
}
