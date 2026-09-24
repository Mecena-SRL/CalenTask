import Foundation

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    var isToday: Bool { Calendar.current.isDateInToday(self) }

    /// "Oggi", "Domani", "Ieri" or a short localized date.
    var dsRelativeLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Oggi" }
        if calendar.isDateInTomorrow(self) { return "Domani" }
        if calendar.isDateInYesterday(self) { return "Ieri" }
        return formatted(.dateTime.day().month(.abbreviated))
    }

    var dsTimeLabel: String {
        formatted(.dateTime.hour().minute())
    }
}
