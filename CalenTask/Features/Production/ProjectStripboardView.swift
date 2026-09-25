import SwiftUI
import SwiftData

/// Il tabellone scene (D54): strisce INT/EST · giorno/notte nei colori
/// classici di produzione, riordinabili e assegnabili ai giorni di ripresa.
/// Tutto offline — il vantaggio sul set.
struct ProjectStripboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project

    @Query(filter: #Predicate<ProductionScene> { $0.deletedAt == nil },
           sort: \ProductionScene.sortOrder)
    private var allScenes: [ProductionScene]

    @State private var editingScene: ProductionScene?
    @State private var isCreatingScene = false
    @State private var editingDay: TodoTask?

    private var scenes: [ProductionScene] {
        allScenes.filter { $0.projectID == project.id }
    }

    /// I giorni di ripresa del progetto, in ordine di data.
    private var shootDays: [TodoTask] {
        project.tasks
            .filter { $0.deletedAt == nil && $0.kind == .shootDay }
            .sorted { ($0.startAt ?? .distantFuture) < ($1.startAt ?? .distantFuture) }
    }

    private func scenes(in day: TodoTask) -> [ProductionScene] {
        scenes.filter { $0.shootDayID == day.id }
    }

    private var unplannedScenes: [ProductionScene] {
        let dayIDs = Set(shootDays.map(\.id))
        return scenes.filter { scene in
            scene.shootDayID.map { !dayIDs.contains($0) } ?? true
        }
    }

    var body: some View {
        Group {
            if scenes.isEmpty && shootDays.isEmpty {
                DSEmptyState(
                    icon: "film.stack",
                    title: "Nessuna scena",
                    subtitle: "Spezza la sceneggiatura in strisce e distribuiscile nei giorni di ripresa.",
                    actionTitle: "Nuova scena",
                    action: { isCreatingScene = true }
                )
            } else {
                List {
                    ForEach(shootDays, id: \.id) { day in
                        daySection(day)
                    }

                    Section {
                        ForEach(unplannedScenes, id: \.id) { scene in
                            stripRow(scene)
                        }
                        .onMove { from, to in
                            move(from: from, to: to, within: unplannedScenes)
                        }
                    } header: {
                        HStack {
                            Text("Da pianificare")
                            Spacer()
                            pagesTotal(unplannedScenes)
                        }
                    }

                    Section {
                        Button {
                            isCreatingScene = true
                        } label: {
                            Label("Nuova scena", systemImage: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        Button {
                            createShootDay()
                        } label: {
                            Label("Nuovo giorno di ripresa", systemImage: "movieclapper")
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $editingScene) { scene in
            SceneEditorView(scene: scene, project: project, shootDays: shootDays)
        }
        .sheet(isPresented: $isCreatingScene) {
            SceneEditorView(scene: nil, project: project, shootDays: shootDays)
        }
        .sheet(item: $editingDay) { day in
            ShootDayEditorView(shootDay: day)
        }
    }

    // MARK: Sezione giorno

    private func daySection(_ day: TodoTask) -> some View {
        let dayScenes = scenes(in: day)
        return Section {
            ForEach(dayScenes, id: \.id) { scene in
                stripRow(scene)
            }
            .onMove { from, to in
                move(from: from, to: to, within: dayScenes)
            }
        } header: {
            Button {
                editingDay = day
            } label: {
                HStack(spacing: DS.s) {
                    Image(systemName: "movieclapper")
                        .foregroundStyle(Color(hex: project.colorHex))
                    Text(day.title)
                    if let startAt = day.startAt {
                        Text(startAt.formatted(.dateTime.weekday(.abbreviated).day().month()))
                            .foregroundStyle(.secondary)
                    }
                    if !ConflictService.conflictedContactIDs(for: day, in: modelContext).isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DSColor.overdue)
                            .help("Conflitti di convocazione in questo giorno")
                    }
                    Spacer()
                    pagesTotal(dayScenes)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func pagesTotal(_ scenes: [ProductionScene]) -> some View {
        let total = scenes.reduce(0) { $0 + $1.pageEighths }
        if total > 0 {
            Text(total % 8 == 0 ? "\(total / 8) pag." : "\(total / 8) \(total % 8)/8 pag.")
                .font(.dsCaption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Striscia

    private func stripRow(_ scene: ProductionScene) -> some View {
        Button {
            editingScene = scene
        } label: {
            HStack(spacing: DS.m) {
                // Il colore classico dello stripboard: la striscia parla da sola.
                RoundedRectangle(cornerRadius: 2)
                    .fill(stripColor(scene))
                    .frame(width: 5)
                    .frame(maxHeight: .infinity)

                Text(scene.number)
                    .font(.dsNumeric.weight(.bold))
                    .frame(width: 36, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(scene.slug.isEmpty ? "Scena \(scene.number)" : scene.slug)
                        .font(.dsMeta.weight(.medium))
                        .foregroundStyle(scene.status == .omitted ? .secondary : .primary)
                        .strikethrough(scene.status == .omitted)
                        .lineLimit(1)
                    HStack(spacing: DS.xs) {
                        Text("\(scene.intExt.label) · \(scene.dayNight.shortLabel)")
                            .font(.dsCaption.weight(.semibold))
                            .foregroundStyle(stripColor(scene))
                        if !scene.locationName.isEmpty {
                            Text(scene.locationName)
                                .font(.dsCaption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                if scene.status == .shot {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.dsCaption)
                        .foregroundStyle(DSColor.status(.done))
                }
                Text(scene.pagesLabel)
                    .font(.dsNumeric)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu {
                Button("Da pianificare") { assign(scene, to: nil) }
                ForEach(shootDays, id: \.id) { day in
                    Button(day.title) { assign(scene, to: day) }
                }
            } label: {
                Label("Assegna a…", systemImage: "movieclapper")
            }
            Menu {
                ForEach(SceneStatus.allCases) { status in
                    Button(status.label) {
                        withAnimation(.dsQuick) {
                            scene.status = status
                            scene.updatedAt = .now
                        }
                    }
                }
            } label: {
                Label("Stato", systemImage: "circle.lefthalf.filled")
            }
            Divider()
            Button(role: .destructive) {
                withAnimation(.dsSoft) {
                    scene.deletedAt = .now
                    scene.updatedAt = .now
                }
            } label: {
                Label("Elimina scena", systemImage: "trash")
            }
        }
    }

    /// Colori classici dello stripboard: EST-G gialla, INT-N blu, EST-N verde,
    /// INT-G neutra, alba/tramonto arancio.
    private func stripColor(_ scene: ProductionScene) -> Color {
        switch (scene.intExt, scene.dayNight) {
        case (_, .dawn), (_, .dusk): Color(hex: "#F76B15")
        case (.int, .day): Color(hex: "#64748B")
        case (.ext, .day), (.intExt, .day): Color(hex: "#FFB224")
        case (.int, .night): Color(hex: "#3E63DD")
        case (.ext, .night), (.intExt, .night): Color(hex: "#30A46C")
        }
    }

    // MARK: Mutations

    private func assign(_ scene: ProductionScene, to day: TodoTask?) {
        withAnimation(.dsSoft) {
            scene.shootDayID = day?.id
            scene.sortOrder = (scenes.map(\.sortOrder).max() ?? -1) + 1
            scene.updatedAt = .now
        }
    }

    private func move(from source: IndexSet, to destination: Int, within group: [ProductionScene]) {
        var ordered = group
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, scene) in ordered.enumerated() where scene.sortOrder != index {
            scene.sortOrder = index
            scene.updatedAt = .now
        }
    }

    private func createShootDay() {
        // Il giorno nuovo parte dal giorno dopo l'ultimo, call 8:00 → wrap 19:00.
        let calendar = Calendar.app
        let lastDay = shootDays.compactMap(\.startAt).max()
        let base = lastDay.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
            ?? .now
        let call = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: base) ?? base
        let day = TodoTask(
            workspaceID: project.workspaceID,
            title: "Giorno \(shootDays.count + 1)",
            kind: .shootDay,
            startAt: call,
            endAt: call.addingTimeInterval(11 * 3600),
            createdByID: project.createdByID
        )
        modelContext.insert(day)
        day.project = project
        project.updatedAt = .now
        editingDay = day
    }
}

// MARK: - Editor scena

struct SceneEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var scene: ProductionScene?
    let project: Project
    let shootDays: [TodoTask]

    @State private var number = ""
    @State private var slug = ""
    @State private var intExt: SceneIntExt = .int
    @State private var dayNight: SceneDayNight = .day
    @State private var location = ""
    @State private var pageEighths = 0
    @State private var cast = ""
    @State private var notes = ""
    @State private var shootDayID: UUID?
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("", text: $number, prompt: Text("N."))
                            .labelsHidden()
                            .frame(width: 60)
                        DSPromptField(prompt: "Slugline / sinossi", text: $slug)
                    }
                    Picker("Interno/Esterno", selection: $intExt) {
                        ForEach(SceneIntExt.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Momento", selection: $dayNight) {
                        ForEach(SceneDayNight.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    DSPromptField(prompt: "Location", text: $location)
                    Stepper(value: $pageEighths, in: 0...200) {
                        HStack {
                            Text("Lunghezza")
                            Spacer()
                            Text(pagesLabel)
                                .foregroundStyle(.secondary)
                                .font(.dsNumeric)
                        }
                    }
                    DSPromptField(prompt: "Cast (separato da virgole)", text: $cast)
                }
                Section("Giorno di ripresa") {
                    Picker("Giorno", selection: $shootDayID) {
                        Text("Da pianificare").tag(UUID?.none)
                        ForEach(shootDays, id: \.id) { day in
                            Text(day.title).tag(UUID?.some(day.id))
                        }
                    }
                }
                Section {
                    DSNotesEditor(text: $notes,
                                  placeholder: "Attrezzature speciali, effetti, sicurezza…",
                                  minHeight: 60)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(scene == nil ? "Nuova scena" : "Scena \(number)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(number.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(width: 420, height: 520)
        #endif
    }

    private var pagesLabel: String {
        let whole = pageEighths / 8
        let eighths = pageEighths % 8
        switch (whole, eighths) {
        case (0, 0): return "—"
        case (_, 0): return "\(whole) pag."
        case (0, _): return "\(eighths)/8 pag."
        default: return "\(whole) \(eighths)/8 pag."
        }
    }

    private func load() {
        guard !didLoad, let scene else { return }
        didLoad = true
        number = scene.number
        slug = scene.slug
        intExt = scene.intExt
        dayNight = scene.dayNight
        location = scene.locationName
        pageEighths = scene.pageEighths
        cast = scene.castNames.joined(separator: ", ")
        notes = scene.notes
        shootDayID = scene.shootDayID
    }

    private func save() {
        let castNames = cast
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let scene {
            scene.number = number
            scene.slug = slug
            scene.intExt = intExt
            scene.dayNight = dayNight
            scene.locationName = location
            scene.pageEighths = pageEighths
            scene.castNames = castNames
            scene.notes = notes
            scene.shootDayID = shootDayID
            scene.updatedAt = .now
        } else {
            let created = ProductionScene(
                workspaceID: project.workspaceID,
                projectID: project.id,
                number: number,
                slug: slug,
                intExt: intExt,
                dayNight: dayNight,
                locationName: location,
                pageEighths: pageEighths,
                sortOrder: Int(Date.now.timeIntervalSince1970)
            )
            created.castNames = castNames
            created.notes = notes
            created.shootDayID = shootDayID
            modelContext.insert(created)
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    let preview = PreviewSampleData.make()
    return ProjectStripboardView(project: preview.project)
        .modelContainer(preview.container)
}
