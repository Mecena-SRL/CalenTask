import SwiftUI

/// Call sheet PDF (D56): generata dal giorno di ripresa — progetto, orari,
/// location, meteo, troupe convocata e scene del giorno. Tutto offline,
/// condivisibile con un tap (il vantaggio dichiarato su Yamdu).
@MainActor
enum CallSheetService {
    static func makePDF(
        project: Project?,
        day: TodoTask,
        crew: [(assignment: CrewAssignment, contact: Contact)],
        scenes: [ProductionScene]
    ) -> URL? {
        let document = CallSheetDocument(
            project: project, day: day, crew: crew, scenes: scenes
        )
        .frame(width: 595)            // larghezza A4 in punti
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: document)
        renderer.proposedSize = ProposedViewSize(width: 595, height: nil)

        let dayLabel = (day.startAt ?? .now).formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CallSheet \(dayLabel).pdf")

        var rendered = false
        renderer.render { size, renderInContext in
            var mediaBox = CGRect(
                origin: .zero,
                size: CGSize(width: 595, height: max(size.height, 842))
            )
            guard
                let consumer = CGDataConsumer(url: url as CFURL),
                let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
            else { return }
            pdfContext.beginPDFPage(nil)
            // Il contenuto parte dall'alto della pagina.
            pdfContext.translateBy(x: 0, y: mediaBox.height - size.height)
            renderInContext(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
            rendered = true
        }
        return rendered ? url : nil
    }
}

/// Il documento, impaginato in SwiftUI e reso in PDF.
private struct CallSheetDocument: View {
    let project: Project?
    let day: TodoTask
    let crew: [(assignment: CrewAssignment, contact: Contact)]
    let scenes: [ProductionScene]

    private var tint: Color {
        project.map { Color(hex: $0.colorHex) } ?? Color(hex: "#0E7490")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            infoRow
            if !crew.isEmpty {
                table(title: "TROUPE E RISORSE") {
                    ForEach(crew, id: \.assignment.id) { item in
                        gridRow(
                            leading: item.contact.name,
                            middle: item.assignment.roleOverride.isEmpty
                                ? item.contact.role : item.assignment.roleOverride,
                            detail: item.contact.phone,
                            trailing: (item.assignment.callTime ?? day.startAt)?
                                .formatted(.dateTime.hour().minute()) ?? "—"
                        )
                    }
                }
            }
            if !scenes.isEmpty {
                table(title: "SCENE") {
                    ForEach(scenes, id: \.id) { scene in
                        gridRow(
                            leading: "Scena \(scene.number)",
                            middle: "\(scene.intExt.label) · \(scene.dayNight.label)"
                                + (scene.locationName.isEmpty ? "" : " · \(scene.locationName)"),
                            detail: scene.slug,
                            trailing: scene.pagesLabel
                        )
                    }
                }
            }
            if !day.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOTE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tint)
                    Text(day.notes)
                        .font(.system(size: 10))
                }
            }
            Text("Generata con CalenTask · \(Date.now.formatted(.dateTime.day().month().year().hour().minute()))")
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(28)
        .frame(width: 595, alignment: .topLeading)
        .background(Color.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(project?.name ?? "Produzione")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Text("CALL SHEET")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(tint)
            }
            Text(day.title)
                .font(.system(size: 12, weight: .semibold))
            Rectangle().fill(tint).frame(height: 3)
        }
    }

    private var infoRow: some View {
        HStack(alignment: .top, spacing: 18) {
            infoBox("DATA", (day.startAt ?? .now)
                .formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
            infoBox("CALL", day.startAt?.formatted(.dateTime.hour().minute()) ?? "—")
            infoBox("WRAP", day.endAt?.formatted(.dateTime.hour().minute()) ?? "—")
            if let location = day.locationName, !location.isEmpty {
                infoBox("LOCATION", location)
            }
            if let startAt = day.startAt,
               let forecast = WeatherService.shared.forecast(for: startAt) {
                infoBox("METEO", "\(Int(forecast.tMin.rounded()))–\(forecast.tMaxLabel)")
            }
        }
    }

    private func infoBox(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 10, weight: .medium))
        }
    }

    private func table(title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            VStack(spacing: 0) {
                rows()
            }
            .overlay(Rectangle().stroke(Color.black.opacity(0.15), lineWidth: 0.5))
        }
    }

    private func gridRow(
        leading: String, middle: String, detail: String, trailing: String
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(leading)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 120, alignment: .leading)
            Text(middle)
                .font(.system(size: 9))
                .frame(width: 150, alignment: .leading)
            Text(detail)
                .font(.system(size: 9))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(trailing)
                .font(.system(size: 9, weight: .medium))
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 0.5)
        }
    }
}
