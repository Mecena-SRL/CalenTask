import Foundation

extension Date {
    var startOfDay: Date { Calendar.app.startOfDay(for: self) }

    var isToday: Bool { Calendar.app.isDateInToday(self) }

    /// "Oggi", "Domani", "Ieri" or a short localized date.
    var dsRelativeLabel: String {
        let calendar = Calendar.app
        if calendar.isDateInToday(self) { return "Oggi" }
        if calendar.isDateInTomorrow(self) { return "Domani" }
        if calendar.isDateInYesterday(self) { return "Ieri" }
        return formatted(.dateTime.day().month(.abbreviated))
    }

    var dsTimeLabel: String {
        formatted(.dateTime.hour().minute())
    }
}
