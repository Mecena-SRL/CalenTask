import WidgetKit
import SwiftUI

// MARK: - Snapshot (mirror)

/// ⚠️ Mirror of `WidgetSnapshot` in CalenTask/Support/WidgetBridge.swift.
/// The app writes it as JSON into the App Group container; keep in sync.
struct WidgetSnapshot: Codable {
    struct Item: Codable, Identifiable {
        var id: UUID
        var title: String
        var timeLabel: String?
        var colorHex: String?
        var isEvent: Bool
        var isDone: Bool
    }

    var generatedAt: Date
    var dayLabel: String
    var items: [Item]
    var overdueCount: Int
    var inboxCount: Int
}

enum SnapshotStore {
    static let appGroupID = "group.it.mecena.CalenTask"
    static let snapshotFilename = "widget-snapshot.json"

    static func load() -> WidgetSnapshot? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFilename),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

// MARK: - Timeline

struct AgendaEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        AgendaEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        completion(AgendaEntry(date: .now, snapshot: SnapshotStore.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        let snapshot = SnapshotStore.load() ?? .empty
        let calendar = Calendar.current
        let now = Date.now
        // #14 — una entry anche a mezzanotte: lì la view riconosce lo
        // snapshot di ieri e smette di spacciarlo per "oggi".
        var entries = [AgendaEntry(date: now, snapshot: snapshot)]
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(AgendaEntry(date: midnight, snapshot: snapshot))
        }
        let next = calendar.date(byAdding: .hour, value: 1, to: now)!
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

// MARK: - Widget

struct TodayAgendaWidget: Widget {
    let kind = "TodayAgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgendaProvider()) { entry in
            AgendaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Oggi")
        .description("L'agenda di oggi a colpo d'occhio: la modalità rapida, in piccolo.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct AgendaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AgendaEntry

    /// #14 — lo snapshot lo scrive l'app: dopo mezzanotte (o se non viene
    /// aperta da giorni) è di un altro giorno. Niente elenco vecchio
    /// spacciato per "oggi": data corrente e invito ad aprire l'app.
    private var isStale: Bool {
        !Calendar.current.isDate(entry.snapshot.generatedAt, inSameDayAs: entry.date)
    }

    private var snapshot: WidgetSnapshot {
        guard isStale else { return entry.snapshot }
        var current = entry.snapshot
        current.items = []
        current.dayLabel = entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return current
    }

    private static let staleMessage = "Apri CalenTask per aggiornare"

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        default:
            listView
        }
    }

    // Small: counts + the next thing to do.
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            if let next = snapshot.items.first(where: { !$0.isDone }) {
                VStack(alignment: .leading, spacing: 2) {
                    if let time = next.timeLabel {
                        Text(time)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(next.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(3)
                }
            } else {
                Text(isStale ? Self.staleMessage : "Tutto fatto ✨")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            counters
        }
    }

    // Medium/large: the quick-mode list, shrunk.
    private var listView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                header
                Spacer()
                counters
            }
            if snapshot.items.isEmpty {
                Spacer()
                Text(isStale ? Self.staleMessage : "Niente in agenda oggi. Cattura un'idea ⚡️")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                let limit = family == .systemLarge ? 8 : 3
                ForEach(snapshot.items.prefix(limit)) { item in
                    itemRow(item)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        Text(snapshot.dayLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .lineLimit(1)
    }

    private var counters: some View {
        HStack(spacing: 8) {
            if snapshot.overdueCount > 0 {
                Label("\(snapshot.overdueCount)", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            Label("\(snapshot.inboxCount)", systemImage: "tray")
                .foregroundStyle(.secondary)
        }
        .font(.caption2.weight(.medium))
        .labelStyle(.titleAndIcon)
    }

    private func itemRow(_ item: WidgetSnapshot.Item) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(item.colorHex.map { Color(widgetHex: $0) } ?? .accentColor)
                .frame(width: 3, height: 16)
            Image(systemName: item.isDone
                  ? "checkmark.circle.fill"
                  : item.isEvent ? "calendar" : "circle")
                .font(.caption)
                .foregroundStyle(item.isDone ? .green : .secondary)
            Text(item.title)
                .font(.caption.weight(.medium))
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let time = item.timeLabel {
                Text(time)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Helpers

extension Color {
    /// Local "#RRGGBB" parser (the DS one lives in the app target).
    init(widgetHex hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension WidgetSnapshot {
    static let empty = WidgetSnapshot(
        generatedAt: .now, dayLabel: "Oggi", items: [],
        overdueCount: 0, inboxCount: 0
    )

    static let sample = WidgetSnapshot(
        generatedAt: .now,
        dayLabel: "martedì 10 giugno",
        items: [
            Item(id: UUID(), title: "Sopralluogo location villa",
                 timeLabel: "10:30", colorHex: "#0E7490", isEvent: true, isDone: false),
            Item(id: UUID(), title: "Chiamare il direttore della fotografia",
                 timeLabel: "15:00", colorHex: "#0E7490", isEvent: false, isDone: false),
            Item(id: UUID(), title: "Preventivo noleggio camera",
                 timeLabel: nil, colorHex: nil, isEvent: false, isDone: true),
        ],
        overdueCount: 1,
        inboxCount: 3
    )
}

#Preview(as: .systemMedium) {
    TodayAgendaWidget()
} timeline: {
    AgendaEntry(date: .now, snapshot: .sample)
}
