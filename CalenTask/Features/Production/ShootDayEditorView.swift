import SwiftUI
import SwiftData

/// Il giorno di ripresa (D56): orari, location, troupe convocata (con
/// conflitti evidenziati) e scene del giorno. Da qui esce la call sheet PDF.
struct ShootDayEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var shootDay: TodoTask

    @Query(filter: #Predicate<Contact> { $0.deletedAt == nil }, sort: \Contact.name)
    private var allContacts: [Contact]

    @Query(filter: #Predicate<CrewAssignment> { $0.deletedAt == nil })
    private var allAssignments: [CrewAssignment]

    @Query(filter: #Predicate<ProductionScene> { $0.deletedAt == nil },
           sort: \ProductionScene.sortOrder)
    private var allScenes: [ProductionScene]

    @State private var pdfURL: URL?
    #if os(iOS)
    @State private var showsMailCompose = false
    #endif

    private var assignments: [CrewAssignment] {
        allAssignments.filter { $0.taskID == shootDay.id }
    }

    private var dayScenes: [ProductionScene] {
        allScenes.filter { $0.shootDayID == shootDay.id }
    }

    private var availableContacts: [Contact] {
        let assigned = Set(assignments.map(\.contactID))
        return allContacts.filter {
            $0.workspaceID == shootDay.workspaceID && !assigned.contains($0.id)
        }
    }

    private func contact(for assignment: CrewAssignment) -> Contact? {
        allContacts.first { $0.id == assignment.contactID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Giorno") {
                    DSPromptField(prompt: "Titolo (es. Giorno 3 — Esterni porto)",
                                  text: $shootDay.title)
                    DSDateField(
                        label: "Call",
                        systemImage: "sunrise",
                        tint: Color(hex: "#F76B15"),
                        date: callBinding,
                        includesTime: true
                    )
                    DSDateField(
                        label: "Wrap",
                        systemImage: "sunset",
                        tint: Color(hex: "#6E56CF"),
                        date: wrapBinding,
                        includesTime: true
                    )
                    DSPromptField(prompt: "Location", text: locationBinding)
                }

                crewSection
                scenesSection

                Section("Note per la troupe") {
                    DSNotesEditor(text: $shootDay.notes,
                                  placeholder: "Parcheggio, contatti, sicurezza…",
                                  minHeight: 60)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Giorno di ripresa")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        shootDay.touch()
                        try? modelContext.save()
                        dismiss()
                    }
                }
                ToolbarItem {
                    Menu {
                        // D58: ODG via mail alla troupe, tutto precompilato.
                        Button {
                            sendCallSheetByEmail()
                        } label: {
                            Label("Invia ODG alla troupe…", systemImage: "paperplane")
                        }
                        .disabled(crewEmails.isEmpty || !EmailService.canCompose)
                        if let pdfURL {
                            ShareLink(item: pdfURL) {
                                Label("Condividi PDF…", systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button {
                                generateCallSheet()
                            } label: {
                                Label("Genera PDF", systemImage: "doc.richtext")
                            }
                        }
                    } label: {
                        Label("Call sheet", systemImage: "doc.richtext")
                    }
                }
            }
            // Ogni modifica invalida il PDF già generato.
            .onChange(of: shootDay.updatedAt) { _, _ in pdfURL = nil }
            #if os(iOS)
            .sheet(isPresented: $showsMailCompose) {
                MailComposeView(
                    recipients: crewEmails,
                    subject: emailSubject,
                    body: emailBody,
                    attachment: pdfURL
                )
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 540)
        #endif
    }

    // MARK: Troupe

    private var crewSection: some View {
        Section {
            let conflicted = ConflictService.conflictedContactIDs(
                for: shootDay, in: modelContext
            )
            ForEach(assignments, id: \.id) { assignment in
                if let contact = contact(for: assignment) {
                    crewRow(assignment: assignment, contact: contact,
                            hasConflict: conflicted.contains(contact.id))
                }
            }
            if availableContacts.isEmpty && assignments.isEmpty {
                Text("La rubrica è vuota: aggiungi troupe e attrezzatura da Progetti → Strumenti → Troupe e risorse.")
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
            } else if !availableContacts.isEmpty {
                Menu {
                    ForEach(ContactKind.allCases) { kind in
                        let items = availableContacts.filter { $0.kind == kind }
                        if !items.isEmpty {
                            Section(kind.label) {
                                ForEach(items, id: \.id) { contact in
                                    Button(contact.name) { convoca(contact) }
                                }
                            }
                        }
                    }
                } label: {
                    Label("Convoca…", systemImage: "person.badge.plus")
                        .foregroundStyle(Color.accentColor)
                }
            }
        } header: {
            Text("Troupe e risorse")
        } footer: {
            if !assignments.isEmpty {
                Text("⚠️ = già convocati altrove lo stesso giorno.")
                    .font(.dsCaption)
            }
        }
    }

    private func crewRow(
        assignment: CrewAssignment, contact: Contact, hasConflict: Bool
    ) -> some View {
        HStack(spacing: DS.m) {
            Image(systemName: contact.kind.systemImage)
                .font(.dsCaption)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.name)
                    .font(.dsMeta.weight(.medium))
                if !contact.role.isEmpty {
                    Text(contact.role)
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                }
            }
            if hasConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.dsCaption)
                    .foregroundStyle(DSColor.overdue)
                    .help("Già convocato altrove in questa giornata")
            }
            Spacer()
            Button(role: .destructive) {
                withAnimation(.dsSoft) {
                    assignment.deletedAt = .now
                    assignment.updatedAt = .now
                    shootDay.touch()
                }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private func convoca(_ contact: Contact) {
        withAnimation(.dsQuick) {
            modelContext.insert(CrewAssignment(
                workspaceID: shootDay.workspaceID,
                contactID: contact.id,
                taskID: shootDay.id
            ))
            shootDay.touch()
        }
    }

    // MARK: Scene

    private var scenesSection: some View {
        Section {
            if dayScenes.isEmpty {
                Text("Assegna le scene dal Tabellone (vista Scene del progetto).")
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dayScenes, id: \.id) { scene in
                    HStack(spacing: DS.m) {
                        Text(scene.number)
                            .font(.dsNumeric.weight(.bold))
                            .frame(width: 34, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(scene.slug.isEmpty ? "Scena \(scene.number)" : scene.slug)
                                .font(.dsMeta)
                                .lineLimit(1)
                            Text("\(scene.intExt.label) · \(scene.dayNight.label) · \(scene.pagesLabel) pag.")
                                .font(.dsCaption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            withAnimation(.dsSoft) {
                                scene.shootDayID = nil
                                scene.updatedAt = .now
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            HStack {
                Text("Scene del giorno")
                Spacer()
                let total = dayScenes.reduce(0) { $0 + $1.pageEighths }
                if total > 0 {
                    Text("\(total / 8) \(total % 8)/8 pagine")
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Bindings

    private var callBinding: Binding<Date?> {
        Binding(
            get: { shootDay.startAt },
            set: { newValue in
                shootDay.startAt = newValue
                if let newValue, let endAt = shootDay.endAt, endAt <= newValue {
                    shootDay.endAt = newValue.addingTimeInterval(10 * 3600)
                }
                shootDay.touch()
            }
        )
    }

    private var wrapBinding: Binding<Date?> {
        Binding(
            get: { shootDay.endAt },
            set: { shootDay.endAt = $0; shootDay.touch() }
        )
    }

    private var locationBinding: Binding<String> {
        Binding(
            get: { shootDay.locationName ?? "" },
            set: { shootDay.locationName = $0.isEmpty ? nil : $0; shootDay.touch() }
        )
    }

    // MARK: Call sheet

    private func generateCallSheet() {
        let crew = assignments.compactMap { assignment in
            contact(for: assignment).map { (assignment: assignment, contact: $0) }
        }
        pdfURL = CallSheetService.makePDF(
            project: shootDay.project,
            day: shootDay,
            crew: crew,
            scenes: dayScenes
        )
    }

    // MARK: ODG via email (D58)

    private var crewEmails: [String] {
        assignments
            .compactMap { contact(for: $0)?.email }
            .filter { !$0.isEmpty }
    }

    private var emailSubject: String {
        let date = (shootDay.startAt ?? .now)
            .formatted(.dateTime.weekday(.wide).day().month(.wide))
        return "ODG · \(shootDay.title) · \(date)"
    }

    private var emailBody: String {
        var lines = ["Ciao,", "", "in allegato l'ordine del giorno per \(shootDay.title)."]
        if let call = shootDay.startAt {
            lines.append("Call: \(call.formatted(.dateTime.hour().minute()))")
        }
        if let location = shootDay.locationName, !location.isEmpty {
            lines.append("Location: \(location)")
        }
        lines.append(contentsOf: ["", "A presto."])
        return lines.joined(separator: "\n")
    }

    private func sendCallSheetByEmail() {
        if pdfURL == nil { generateCallSheet() }
        #if os(macOS)
        EmailService.compose(
            to: crewEmails, subject: emailSubject,
            body: emailBody, attachment: pdfURL
        )
        #else
        showsMailCompose = true
        #endif
    }
}
