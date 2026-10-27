import Foundation
import Testing
@testable import CalenTask

/// #19 — indice del calendario: multi-giorno, tutto il giorno, scadenze e
/// attività senza data.
@MainActor
struct CalendarTaskIndexTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }()
    private let workspace = UUID(), author = UUID()

    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    private func task(
        _ title: String, start: Date? = nil, end: Date? = nil, due: Date? = nil,
        allDay: Bool = false, status: TaskStatus = .todo
    ) -> TodoTask {
        TodoTask(workspaceID: workspace, title: title, status: status,
                 startAt: start, endAt: end, dueAt: due, allDay: allDay,
                 createdByID: author)
    }

    /// Un evento con orario nello stesso giorno è un blocco della griglia.
    @Test func timedEventStaysInTimedLane() {
        let event = task("Riunione", start: date(10, 9), end: date(10, 10))
        let index = CalendarTaskIndex(tasks: [event], calendar: calendar)
        #expect(index.timedTasks(on: date(10, 15)).count == 1)
        #expect(index.allDayTasks(on: date(10)).isEmpty)
        #expect(index.count(inMonth: date(1)) == 1)
    }

    /// Un evento su più giorni compare in ogni giorno coperto, come barra
    /// "tutto il giorno", e non come blocco orario.
    @Test func multiDayEventCoversEachDay() {
        let event = task("Trasferta", start: date(10, 9), end: date(12, 18))
        let index = CalendarTaskIndex(tasks: [event], calendar: calendar)
        for day in 10...12 {
            #expect(index.tasks(on: date(day)).count == 1)
            #expect(index.allDayTasks(on: date(day)).count == 1)
        }
        #expect(index.tasks(on: date(13)).isEmpty)
        #expect(index.timedTasks(on: date(10)).isEmpty)
    }

    /// Finire a mezzanotte non occupa il giorno successivo (fine esclusiva).
    @Test func endAtMidnightDoesNotSpillOver() {
        let event = task("Serata", start: date(10, 20), end: date(11))
        let index = CalendarTaskIndex(tasks: [event], calendar: calendar)
        #expect(index.tasks(on: date(11)).isEmpty)
        #expect(index.timedTasks(on: date(10)).count == 1)
    }

    /// Inizio e scadenza nello stesso giorno contano una sola volta.
    @Test func startAndDueSameDayCountOnce() {
        let item = task("Consegna", start: date(10, 9), due: date(10, 18))
        let index = CalendarTaskIndex(tasks: [item], calendar: calendar)
        #expect(index.tasks(on: date(10)).count == 1)
    }

    /// La sola scadenza va in "tutto il giorno"; senza date e non fatta è
    /// "non pianificata", se fatta no.
    @Test func dueOnlyAndUnscheduled() {
        let due = task("Scade", due: date(5, 12))
        let open = task("Da pianificare")
        let done = task("Fatta", status: .done)
        let index = CalendarTaskIndex(tasks: [due, open, done], calendar: calendar)
        #expect(index.allDayTasks(on: date(5)).count == 1)
        #expect(index.unscheduled.map(\.title) == ["Da pianificare"])
    }

    /// Il limite di 62 giorni protegge da eventi con fine errata.
    @Test func continuationIsCapped() {
        let event = task("Infinito", start: date(1), end: date(1).addingTimeInterval(400 * 86_400))
        let days = CalendarTaskIndex.continuationDays(
            of: event, from: calendar.startOfDay(for: date(1)), calendar: calendar)
        #expect(days.count == 62)
    }
}
