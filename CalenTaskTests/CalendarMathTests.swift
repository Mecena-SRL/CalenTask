import Foundation
import Testing
@testable import CalenTask

struct CalendarMathTests {
    private var italianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "it_IT")
        calendar.firstWeekday = 2   // Monday
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        italianCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func gridIsAlways6x7() {
        let calendar = italianCalendar
        for month in 1...12 {
            let grid = CalendarMath.monthGrid(for: date(2026, month, 15), calendar: calendar)
            #expect(grid.count == 6)
            #expect(grid.allSatisfy { $0.count == 7 })
        }
    }

    @Test func juneGridStartsOnMonday1st() {
        // June 2026 starts on a Monday: no leading days from May.
        let grid = CalendarMath.monthGrid(for: date(2026, 6, 10), calendar: italianCalendar)
        #expect(italianCalendar.isDate(grid[0][0], inSameDayAs: date(2026, 6, 1)))
    }

    @Test func monthStartingOnSundayHasSixLeadingDays() {
        // March 2026 starts on a Sunday → Monday-first grid shows 6 days of February.
        let grid = CalendarMath.monthGrid(for: date(2026, 3, 1), calendar: italianCalendar)
        #expect(italianCalendar.isDate(grid[0][0], inSameDayAs: date(2026, 2, 23)))
        #expect(italianCalendar.isDate(grid[0][6], inSameDayAs: date(2026, 3, 1)))
    }

    @Test func gridSurvivesDSTTransition() {
        // Europe/Rome enters DST on 29 March 2026; all 42 cells must be distinct days.
        let grid = CalendarMath.monthGrid(for: date(2026, 3, 15), calendar: italianCalendar)
        let days = grid.flatMap { $0 }
        let uniqueDays = Set(days.map { italianCalendar.startOfDay(for: $0) })
        #expect(uniqueDays.count == 42)
    }

    @Test func weekdaySymbolsStartWithMonday() {
        let symbols = CalendarMath.orderedWeekdaySymbols(calendar: italianCalendar)
        #expect(symbols.count == 7)
        #expect(symbols.first == "L")   // Lunedì
        #expect(symbols.last == "D")    // Domenica
    }

    @Test func yearBoundaryNavigation() {
        let calendar = italianCalendar
        let december = date(2026, 12, 15)
        let january = calendar.date(byAdding: .month, value: 1, to: december)!
        let grid = CalendarMath.monthGrid(for: january, calendar: calendar)
        #expect(CalendarMath.isSameMonth(grid[2][3], date(2027, 1, 15), calendar: calendar))
    }
}
