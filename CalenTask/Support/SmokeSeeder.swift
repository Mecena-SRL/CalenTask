import Foundation
import SwiftData

/// Dati di prova per lo smoke test della CI (`.github/scripts/smoke-launch.sh`):
/// si attiva solo con la variabile d'ambiente `CALENTASK_SMOKE_SEED=1` e
/// solo su un archivio senza attività. Copre i casi che il calendario
/// disegna in modo diverso: con orario, tutto il giorno, su più giorni (anche
/// a cavallo del mese), scadenze, sovrapposizioni e un giorno affollato.
@MainActor
enum SmokeSeeder {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["CALENTASK_SMOKE_SEED"] == "1"
    }

    static func seedIfRequested(in context: ModelContext) {
        guard isRequested else { return }
        do {
            var probe = FetchDescriptor<TodoTask>()
            probe.fetchLimit = 1
            guard try context.fetch(probe).isEmpty else { return }
            try seed(in: context)
            Log.store.info("Smoke: dati di prova inseriti.")
        } catch {
            Log.store.error("Smoke: dati di prova non inseriti: \(String(describing: error), privacy: .public)")
        }
    }

    private static func seed(in context: ModelContext) throws {
        let (workspace, me) = try SeedService.ensureSeed(in: context)
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int, hour: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(byAdding: .hour, value: hour, to: base) ?? base
        }
        func add(_ title: String, start: Date? = nil, end: Date? = nil, due: Date? = nil,
                 allDay: Bool = false, status: TaskStatus = .todo) {
            let task = TodoTask(workspaceID: workspace.id, title: title, status: status,
                                startAt: start, endAt: end, dueAt: due, allDay: allDay,
                                createdByID: me.id)
            context.insert(task)
        }

        add("Riunione di produzione", start: day(0, hour: 9), end: day(0, hour: 10))
        add("Sovrapposta", start: day(0, hour: 9), end: day(0, hour: 11))
        add("Pranzo", start: day(0, hour: 13), end: day(0, hour: 14), status: .done)
        add("Consegna montaggio", due: day(2, hour: 18))
        add("Scaduta", due: day(-3, hour: 12))
        add("Ferie", start: day(3), end: day(8), allDay: true)
        add("Trasferta", start: day(-2, hour: 15), end: day(1, hour: 11))
        add("Riprese lunghe", start: day(-20), end: day(20), allDay: true)
        add("Mezzanotte esatta", start: day(5), end: day(6))
        add("Con scadenza dopo", start: day(1, hour: 10), end: day(1, hour: 12), due: day(4))
        add("Senza data")
        for index in 0..<12 {
            add("Affollato \(index + 1)", start: day(1, hour: 8 + index % 10),
                end: day(1, hour: 9 + index % 10))
        }
        try context.save()
    }
}
