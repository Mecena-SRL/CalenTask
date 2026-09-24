import Foundation
import CoreLocation
import Observation

/// Meteo per pianificare (D52): previsioni giornaliere fino a 16 giorni
/// sulla posizione attuale, via Open-Meteo (gratuito, senza chiavi API).
/// La posizione si usa SOLO per il meteo; cache 3 ore, anche offline.
@Observable @MainActor
final class WeatherService: NSObject {
    static let shared = WeatherService()
    static let enabledKey = "weatherEnabled"
    private static let cacheKey = "weatherForecastCache"

    struct DayForecast: Codable {
        let day: Date
        let weatherCode: Int
        let tMax: Double
        let tMin: Double

        var symbolName: String { WeatherService.symbol(for: weatherCode) }
        var tMaxLabel: String { "\(Int(tMax.rounded()))°" }
        var tMinLabel: String { "\(Int(tMin.rounded()))°" }
        var conditionLabel: String { WeatherService.conditionLabel(for: weatherCode) }
    }

    private struct Cache: Codable {
        let fetchedAt: Date
        let days: [DayForecast]
    }

    private(set) var byDay: [Date: DayForecast] = [:]
    private var lastFetchAt: Date?
    private var isFetching = false
    private let locationManager = CLLocationManager()

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        loadCache()
    }

    func forecast(for date: Date) -> DayForecast? {
        guard isEnabled else { return nil }
        return byDay[Calendar.current.startOfDay(for: date)]
    }

    /// Aggiorna se la cache è più vecchia di 3 ore. Chiede il permesso
    /// posizione al primo uso (solo se il meteo è attivo).
    func refreshIfNeeded() {
        guard isEnabled, !isFetching else { return }
        if let lastFetchAt, Date.now.timeIntervalSince(lastFetchAt) < 3 * 3600,
           !byDay.isEmpty {
            return
        }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        #if os(macOS)
        case .authorized, .authorizedAlways:
            locationManager.requestLocation()
        #else
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        #endif
        default:
            break
        }
    }

    // MARK: Fetch

    private func fetch(coordinate: CLLocationCoordinate2D) async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", coordinate.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "16"),
        ]
        guard let url = components.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            apply(days: response.dayForecasts)
            lastFetchAt = .now
            saveCache()
        } catch {
            // Senza rete il meteo semplicemente non appare: nessun errore in UI.
        }
    }

    private func apply(days: [DayForecast]) {
        byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0) })
    }

    // MARK: Cache

    private func loadCache() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.cacheKey),
            let cache = try? JSONDecoder().decode(Cache.self, from: data)
        else { return }
        apply(days: cache.days)
        lastFetchAt = cache.fetchedAt
    }

    private func saveCache() {
        let cache = Cache(fetchedAt: .now, days: Array(byDay.values))
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    // MARK: Codici WMO → SF Symbols

    nonisolated static func conditionLabel(for code: Int) -> String {
        switch code {
        case 0: "Sereno"
        case 1: "Quasi sereno"
        case 2: "Poco nuvoloso"
        case 3: "Coperto"
        case 45, 48: "Nebbia"
        case 51...57: "Pioviggine"
        case 61...67: "Pioggia"
        case 71...77: "Neve"
        case 80...82: "Rovesci"
        case 85, 86: "Neve"
        case 95...99: "Temporale"
        default: "—"
        }
    }

    nonisolated static func symbol(for code: Int) -> String {
        switch code {
        case 0: "sun.max"
        case 1, 2: "cloud.sun"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51...57: "cloud.drizzle"
        case 61...67: "cloud.rain"
        case 71...77: "cloud.snow"
        case 80...82: "cloud.heavyrain"
        case 85, 86: "cloud.snow"
        case 95...99: "cloud.bolt.rain"
        default: "cloud"
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            #if os(macOS)
            if status == .authorized || status == .authorizedAlways {
                self.locationManager.requestLocation()
            }
            #else
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.locationManager.requestLocation()
            }
            #endif
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        Task { @MainActor in
            await self.fetch(coordinate: coordinate)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: Error
    ) {
        // Posizione non disponibile: il meteo resta sull'ultima cache.
    }
}

// MARK: - Open-Meteo DTO

private struct OpenMeteoResponse: Decodable {
    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }

    let daily: Daily

    var dayForecasts: [WeatherService.DayForecast] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return daily.time.indices.compactMap { index in
            guard
                let date = formatter.date(from: daily.time[index]),
                daily.weather_code.indices.contains(index),
                daily.temperature_2m_max.indices.contains(index),
                daily.temperature_2m_min.indices.contains(index)
            else { return nil }
            return WeatherService.DayForecast(
                day: Calendar.current.startOfDay(for: date),
                weatherCode: daily.weather_code[index],
                tMax: daily.temperature_2m_max[index],
                tMin: daily.temperature_2m_min[index]
            )
        }
    }
}
