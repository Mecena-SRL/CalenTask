import Foundation

/// A render-scoped index: one pass over the visible tasks, shared by every
/// calendar scale. It holds live models, so edits continue through SwiftData;
/// no persisted or state cache can become stale after a sync or reschedule.
struct CalendarTaskIndex {
    let tasks: [TodoTask]
    let tasksByDay: [Date: [TodoTask]]
    let countsByDay: [Date: Int]
    let countsByMonth: [Date: Int]
    let timedByDay: [Date: [TodoTask]]
    let allDayByDay: [Date: [TodoTask]]
    let unscheduled: [TodoTask]
    private let calendar: Calendar

    init(tasks: [TodoTask], calendar: Calendar) {
        self.tasks = tasks
        self.calendar = calendar
        var byDay: [Date: [TodoTask]] = [:]
        var timed: [Date: [TodoTask]] = [:]
        var allDay: [Date: [TodoTask]] = [:]
        var unscheduled: [TodoTask] = []
        for task in tasks {
            let startDay = task.startAt.map { calendar.startOfDay(for: $0) }
            let dueDay = task.dueAt.map { calendar.startOfDay(for: $0) }
            if let startDay {
                byDay[startDay, default: []].append(task)
                if !task.allDay { timed[startDay, default: []].append(task) }
            }
            // One item on a day even when both temporal facets land there.
            if let dueDay, dueDay != startDay {
                byDay[dueDay, default: []].append(task)
            }
            if task.allDay, let anchor = startDay ?? dueDay {
                allDay[anchor, default: []].append(task)
            } else if startDay == nil, let dueDay {
                allDay[dueDay, default: []].append(task)
            }
            if startDay == nil, dueDay == nil, !task.isDone {
                unscheduled.append(task)
            }
        }
        tasksByDay = byDay
        countsByDay = byDay.mapValues(\.count)
        timedByDay = timed
        allDayByDay = allDay
        self.unscheduled = unscheduled
        var months: [Date: Int] = [:]
        for (day, items) in byDay {
            months[CalendarMath.startOfMonth(for: day, calendar: calendar), default: 0] += items.count
        }
        countsByMonth = months
    }

    func tasks(on day: Date) -> [TodoTask] {
        tasksByDay[calendar.startOfDay(for: day)] ?? []
    }

    func timedTasks(on day: Date) -> [TodoTask] {
        timedByDay[calendar.startOfDay(for: day)] ?? []
    }

    func allDayTasks(on day: Date) -> [TodoTask] {
        allDayByDay[calendar.startOfDay(for: day)] ?? []
    }

    func count(inMonth month: Date) -> Int {
        countsByMonth[CalendarMath.startOfMonth(for: month, calendar: calendar)] ?? 0
    }
}
