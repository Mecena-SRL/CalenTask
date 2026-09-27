import SwiftUI
import Combine

extension View {
    /// #13 — Esegue `action` quando cambia il giorno con l'app aperta
    /// (mezzanotte) o cambia il fuso orario di sistema (viaggi), passando il
    /// nuovo inizio di "oggi" su `Calendar.app`. Senza, le viste che fissano
    /// "oggi" in uno `@State` restano su ieri finché non vengono ricreate.
    func onDayChange(perform action: @escaping (Date) -> Void) -> some View {
        onReceive(DayChange.publisher) { _ in
            action(Calendar.app.startOfDay(for: .now))
        }
    }
}

private enum DayChange {
    static var publisher: AnyPublisher<Notification, Never> {
        let center = NotificationCenter.default
        return center.publisher(for: .NSCalendarDayChanged)
            .merge(with: center.publisher(for: .NSSystemTimeZoneDidChange))
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}
