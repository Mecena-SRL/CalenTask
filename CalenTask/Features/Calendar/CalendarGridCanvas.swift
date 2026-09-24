import Foundation
import SwiftUI

// Le fondamenta delle griglie orarie (Giorno e Settimana), condivise.
//
// Prima lo sfondo erano CENTINAIA di viste — 24 righe con separatori per
// ogni colonna, più una linea "adesso" per colonna — tutte ri-layoutate a
// ogni frame di pinch e a ogni scroll. Ora è UN `Canvas` (disegno, nessuna
// vista figlia) più una linea "adesso" che si aggiorna da sola ogni minuto.

/// Orario di lavoro: ombreggia le ore fuori e decide dove si apre la griglia.
enum CalendarWorkHours {
    static let startKey = "calendarWorkStartHour"
    static let endKey = "calendarWorkEndHour"
    static let defaultStart = 9
    static let defaultEnd = 18

    /// L'intervallo valido (inizio < fine), altrimenti nessuna ombreggiatura.
    static func range(start: Int, end: Int) -> Range<Int>? {
        let start = min(max(start, 0), 23)
        let end = min(max(end, 1), 24)
        return start < end ? start..<end : nil
    }
}

/// Geometria condivisa: dove cade un orario, dove aprire la griglia.
enum CalendarGridMetrics {
    static func minutesIntoDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func y(for date: Date, hourHeight: CGFloat, calendar: Calendar) -> CGFloat {
        CGFloat(minutesIntoDay(date, calendar: calendar)) / 60 * hourHeight
    }

    /// "09:30" da minuti dall'inizio del giorno.
    static func clockLabel(_ minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 24 * 60)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// "09:30 – 11:00".
    static func rangeLabel(_ startMinutes: Int, _ endMinutes: Int) -> String {
        "\(clockLabel(startMinutes)) – \(clockLabel(endMinutes))"
    }

    /// L'ora da mostrare in cima all'apertura: un'ora prima di adesso se oggi
    /// è visibile (si vede subito cosa c'è ora e dopo), altrimenti l'inizio
    /// della giornata lavorativa.
    static func initialScrollHour(showsToday: Bool, now: Date, workStart: Int, calendar: Calendar) -> Int {
        guard showsToday else { return min(max(workStart, 0), 20) }
        return min(max(calendar.component(.hour, from: now) - 1, 0), 20)
    }
}

/// Lo sfondo della griglia oraria in un solo disegno: fasce fuori orario,
/// colonne del weekend, linee delle ore e delle mezz'ore, separatori delle
/// colonne. Non intercetta i tocchi.
struct CalendarHourGridCanvas: View {
    let hourHeight: CGFloat
    var columns: Int = 1
    var weekendColumns: Set<Int> = []
    var workHours: Range<Int>?

    var body: some View {
        Canvas { context, size in
            let columnCount = max(columns, 1)
            let columnWidth = size.width / CGFloat(columnCount)
            let shade = GraphicsContext.Shading.color(.primary.opacity(0.035))

            if let workHours {
                let topHeight = CGFloat(workHours.lowerBound) * hourHeight
                let bottomY = CGFloat(workHours.upperBound) * hourHeight
                context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: topHeight)), with: shade)
                context.fill(
                    Path(CGRect(x: 0, y: bottomY, width: size.width, height: max(0, size.height - bottomY))),
                    with: shade
                )
            }

            for column in weekendColumns where column < columnCount {
                let rect = CGRect(x: CGFloat(column) * columnWidth, y: 0, width: columnWidth, height: size.height)
                context.fill(Path(rect), with: shade)
            }

            if hourHeight >= 36 {
                var halves = Path()
                for hour in 0..<24 {
                    let y = (CGFloat(hour) + 0.5) * hourHeight
                    halves.move(to: CGPoint(x: 0, y: y))
                    halves.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(halves, with: .color(.primary.opacity(0.06)),
                               style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }

            var hours = Path()
            for hour in 0...24 {
                let y = CGFloat(hour) * hourHeight
                hours.move(to: CGPoint(x: 0, y: y))
                hours.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(hours, with: .color(.primary.opacity(0.11)), lineWidth: 0.5)

            var separators = Path()
            for column in 0..<columnCount {
                let x = CGFloat(column) * columnWidth
                separators.move(to: CGPoint(x: x, y: 0))
                separators.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(separators, with: .color(.primary.opacity(0.08)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// La colonna delle ore a sinistra della griglia. Ogni etichetta è centrata
/// sulla sua linea (come Calendario di Apple) e fa da ancora per lo scroll.
struct CalendarHourLabels: View {
    let hourHeight: CGFloat
    let width: CGFloat
    /// Prefisso degli id di scroll ("hour-8", "week-hour-8"…).
    let idPrefix: String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: width - 6, height: hourHeight, alignment: .topTrailing)
                    .offset(y: -6)
                    .padding(.trailing, 6)
                    .id("\(idPrefix)\(hour)")
            }
        }
        .accessibilityHidden(true)
    }
}

/// La linea "adesso" che si sposta da sola (una volta al minuto): tenue su
/// tutta la griglia, piena col pallino nella colonna di oggi, e l'ora
/// corrente in rosso nel margine delle ore.
struct CalendarNowIndicator: View {
    let hourHeight: CGFloat
    let labelWidth: CGFloat
    var columns: Int = 1
    /// La colonna di oggi, se oggi è visibile.
    var todayColumn: Int?

    private let calendar = Calendar.app

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            GeometryReader { geo in
                let y = CalendarGridMetrics.y(for: timeline.date, hourHeight: hourHeight, calendar: calendar)
                let gridWidth = max(0, geo.size.width - labelWidth)
                let columnWidth = gridWidth / CGFloat(max(columns, 1))
                ZStack(alignment: .topLeading) {
                    if columns > 1 {
                        Rectangle()
                            .fill(DSColor.overdue.opacity(0.28))
                            .frame(width: gridWidth, height: 1)
                            .offset(x: labelWidth, y: y)
                    }
                    if let todayColumn {
                        DSNowLine()
                            .frame(width: columnWidth + 3.5)
                            .offset(x: labelWidth + CGFloat(todayColumn) * columnWidth - 3.5, y: y - 3.5)
                        Text(timeline.date.dsTimeLabel)
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DSColor.overdue, in: Capsule())
                            .frame(width: labelWidth - 2, alignment: .trailing)
                            .offset(y: y - 7)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
