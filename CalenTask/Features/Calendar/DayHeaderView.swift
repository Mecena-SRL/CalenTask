import SwiftUI

/// Header unificato della vista Giorno (v8): un colpo d'occhio sul giorno —
/// etichetta relativa, riepilogo (eventi · ore impegnate · arco orario) e il
/// **meteo come protagonista** in uno spazio dedicato. Condiviso da Agenda e
/// Griglia, così il titolo non è più duplicato e la Griglia ha finalmente un
/// header.
struct DayHeaderView: View {
    let day: Date
    let tasks: [TodoTask]
    var showsSummary = true
    var showsWeather = true

    private let calendar = Calendar.app

    var body: some View {
        HStack(alignment: .center, spacing: DS.m) {
            if showsSummary {
                VStack(alignment: .leading, spacing: DS.xs) {
                    if let relativeLabel {
                        Text(relativeLabel)
                            .font(.dsCaption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                    }
                    summaryLine
                }
            }

            Spacer(minLength: DS.s)

            if showsWeather, let forecast = WeatherService.shared.forecast(for: day) {
                DayWeatherBadge(forecast: forecast)
            }
        }
    }

    // MARK: Etichetta relativa
    // Solo Oggi/Domani/Ieri: la data piena vive già nella barra del titolo.

    private var relativeLabel: String? {
        if calendar.isDateInToday(day) { return "Oggi" }
        if calendar.isDateInTomorrow(day) { return "Domani" }
        if calendar.isDateInYesterday(day) { return "Ieri" }
        return nil
    }

    // MARK: Riepilogo

    private var timed: [TodoTask] {
        tasks
            .filter { task in
                guard !task.allDay, let startAt = task.startAt else { return false }
                return calendar.isDate(startAt, inSameDayAs: day)
            }
            .sorted { ($0.startAt ?? .distantPast) < ($1.startAt ?? .distantPast) }
    }

    @ViewBuilder
    private var summaryLine: some View {
        let timed = timed
        if timed.isEmpty {
            Text(deadlineCount > 0 ? "\(deadlineCount) \(deadlineCount == 1 ? "scadenza" : "scadenze")" : "Giornata libera")
                .font(.dsMeta.weight(.medium))
                .foregroundStyle(.primary)
        } else {
            HStack(spacing: DS.s) {
                Label("\(timed.count) \(timed.count == 1 ? "evento" : "eventi")", systemImage: "calendar")
                if let busy = busyLabel(for: timed) {
                    Label(busy, systemImage: "clock")
                }
                if let span = spanLabel(for: timed) {
                    Text(span)
                }
            }
            .font(.dsMeta)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
    }

    private var deadlineCount: Int {
        tasks.filter { task in
            guard let dueAt = task.dueAt, !task.isDone else { return false }
            let sameDay = calendar.isDate(dueAt, inSameDayAs: day)
            let timedToday = task.startAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false
            return sameDay && !timedToday
        }.count
    }

    /// Minuti totali impegnati dagli eventi con orario.
    private func busyMinutes(for timed: [TodoTask]) -> Int {
        timed.reduce(0) { total, task in
            guard let startAt = task.startAt else { return total }
            let end = task.endAt ?? startAt.addingTimeInterval(3600)
            return total + max(0, Int(end.timeIntervalSince(startAt) / 60))
        }
    }

    private func busyLabel(for timed: [TodoTask]) -> String? {
        let busyMinutes = busyMinutes(for: timed)
        guard busyMinutes > 0 else { return nil }
        let hours = busyMinutes / 60
        let minutes = busyMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    private func spanLabel(for timed: [TodoTask]) -> String? {
        guard let first = timed.first?.startAt else { return nil }
        let end = timed.compactMap { task in
            task.startAt.map { task.endAt ?? $0.addingTimeInterval(3600) }
        }.max() ?? first
        return "\(first.dsTimeLabel)–\(end.dsTimeLabel)"
    }
}

// MARK: - Meteo del giorno

/// Il meteo del giorno in uno spazio proprio: simbolo multicolor + condizione
/// testuale + massima/minima, con una tinta che cambia col tempo.
struct DayWeatherBadge: View {
    let forecast: WeatherService.DayForecast

    private var tint: Color {
        switch forecast.weatherCode {
        case 0, 1: Color(hex: "#FFB224")          // sereno — ambra
        case 2, 3, 45, 48: Color(hex: "#8B97A7")  // nuvole/nebbia — grigio
        case 51...67, 80...82: Color(hex: "#3E63DD") // pioggia — blu
        case 71...77, 85, 86: Color(hex: "#12A594")  // neve — verde acqua
        case 95...99: Color(hex: "#6E56CF")       // temporale — viola
        default: Color(hex: "#8B97A7")
        }
    }

    var body: some View {
        HStack(spacing: DS.s) {
            Image(systemName: forecast.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.title2)
            VStack(alignment: .leading, spacing: 0) {
                Text(forecast.conditionLabel)
                    .font(.dsCaption.weight(.medium))
                    .foregroundStyle(.primary)
                HStack(spacing: DS.xs) {
                    Text(forecast.tMaxLabel)
                        .font(.dsNumeric.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(forecast.tMinLabel)
                        .font(.dsNumeric)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, DS.m)
        .padding(.vertical, DS.s)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.medium)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meteo: \(forecast.conditionLabel), massima \(forecast.tMaxLabel), minima \(forecast.tMinLabel)")
    }
}
