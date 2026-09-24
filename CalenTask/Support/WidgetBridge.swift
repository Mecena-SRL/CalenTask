import Foundation
import SwiftData
import WidgetKit

/// Bridge to the widget (D11/M7): the app serializes a small JSON snapshot
/// of today into the App Group container; the widget only decodes it.
/// No SwiftData in the extension — fast, robust, no shared-store headaches.
///
/// ⚠️ `WidgetSnapshot` is duplicated in Widget/Widget.swift (separate target,
/// no shared module). Keep the two definitions in sync.
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

@MainActor
enum WidgetBridge {
    static let appGroupID = "group.it.mecena.CalenTask"
    static let snapshotFilename = "widget-snapshot.json"

    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFilename)
    }

    /// Rebuilds today's snapshot and pokes WidgetKit. Cheap — call freely
    /// on launch and when the scene goes to the background.
    static func refresh(in context: ModelContext) {
        guard let url = snapshotURL else { return }
        do {
            let snapshot = try makeSnapshot(in: context)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: url, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Never let widget plumbing break the app.
            #if DEBUG
            print("WidgetBridge refresh failed: \(error)")
            #endif
        }
    }

    private static func makeSnapshot(in context: ModelContext) throws -> WidgetSnapshot {
        let calendar = Calendar.current
        let today = Date.now.startOfDay

        let open = try context.fetch(FetchDescriptor(predicate: TodoTask.openPredicate))
        let inbox = try context.fetchCount(FetchDescriptor(predicate: TodoTask.inboxPredicate))

        let todayTasks = open
            .filter { task in
                let dates = [task.startAt, task.dueAt, task.remindAt].compactMap(\.self)
                return dates.contains { calendar.isDate($0, inSameDayAs: today) }
            }
            .sorted { agendaDate($0) < agendaDate($1) }

        let overdue = open.filter { task in
            guard let dueAt = task.dueAt else { return false }
            return dueAt < today
        }

        let items = todayTasks.prefix(8).map { task in
            WidgetSnapshot.Item(
                id: task.id,
                title: task.title,
                timeLabel: timeLabel(for: task),
                colorHex: task.project?.colorHex,
                isEvent: task.kind == .event,
                isDone: task.isDone
            )
        }

        return WidgetSnapshot(
            generatedAt: .now,
            dayLabel: today.formatted(.dateTime.weekday(.wide).day().month(.wide)),
            items: Array(items),
            overdueCount: overdue.count,
            inboxCount: inbox
        )
    }

    private static func agendaDate(_ task: TodoTask) -> Date {
        task.startAt ?? task.remindAt ?? task.dueAt ?? .distantFuture
    }

    private static func timeLabel(for task: TodoTask) -> String? {
        if task.allDay { return "Tutto il giorno" }
        return (task.startAt ?? task.remindAt)?.dsTimeLabel
    }
}
