import SwiftUI
import SwiftData

/// Shared rapid-capture core: one text field + Return saves to the Inbox.
/// Stays open after saving for serial entry; date and reminder are optional.
struct QuickCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isTitleFocused: Bool

    @AppStorage(WorkspaceScope.storageKey) private var scopeRaw = "all"
    @Query(filter: #Predicate<Workspace> { $0.deletedAt == nil })
    private var workspaces: [Workspace]

    @State private var title = ""
    @State private var dueDate: Date?
    @State private var remindEnabled = false
    @State private var remindDate = defaultReminder
    @State private var savedCount = 0
    @State private var showsComposer = false
    // Quick add esteso (S4/D60): chip annullabili + progetto dall'autocomplete.
    @State private var selectedProject: Project?
    @State private var suppressDate = false
    @State private var suppressPriority = false
    @State private var speech = SpeechCaptureService.shared

    var onDone: (() -> Void)? = nil
    /// Pre-fills the due date (e.g. capture from a calendar day).
    var initialDueDate: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.m) {
            HStack(spacing: DS.m) {
                TextField("Cosa c'è da fare?", text: $title)
                    .textFieldStyle(.plain)
                    .font(.dsRowTitle)
                    .focused($isTitleFocused)
                    .onSubmit(save)
                // D66 — voice capture: parla, il testo arriva nel campo.
                Button {
                    speech.toggle()
                } label: {
                    Image(systemName: speech.isRecording ? "waveform.circle.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(speech.isRecording ? DSColor.overdue : Color.secondary)
                        .symbolEffect(.pulse, isActive: speech.isRecording)
                }
                .buttonStyle(.plain)
                .help("Detta l'attività")
                .accessibilityLabel(speech.isRecording ? "Ferma dettatura" : "Detta l'attività")
                if savedCount > 0 {
                    Label("\(savedCount)", systemImage: "checkmark.circle.fill")
                        .font(.dsNumeric)
                        .foregroundStyle(DSColor.status(.done))
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("\(savedCount) attività salvate")
                }
            }

            CaptureAssistView(
                text: $title,
                selectedProject: $selectedProject,
                suppressDate: $suppressDate,
                suppressPriority: $suppressPriority
            )

            DateChipPicker(label: "Scadenza", date: $dueDate)

            HStack(spacing: DS.m) {
                Toggle(isOn: $remindEnabled.animation()) {
                    Label("Promemoria", systemImage: "bell")
                        .font(.dsMeta)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(remindEnabled ? Color.accentColor : Color.secondary)

                if remindEnabled {
                    DatePicker("", selection: $remindDate)
                        .labelsHidden()
                }
                Spacer()
                // "Espandi": hand the draft to the full composer (D9).
                Button {
                    showsComposer = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Apri il composer completo")
                .accessibilityLabel("Apri il composer completo")

                Button("Salva", action: save)
                    .buttonStyle(.dsProminent)
                    .disabled(trimmedTitle.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(DS.l)
        .onAppear {
            dueDate = initialDueDate
            isTitleFocused = true
        }
        .onChange(of: speech.transcript) { _, transcript in
            if !transcript.isEmpty { title = transcript }
        }
        .onDisappear {
            if speech.isRecording { speech.stop() }
        }
        .sheet(isPresented: $showsComposer, onDismiss: { isTitleFocused = true }) {
            TaskComposerView(initialTitle: trimmedTitle, initialDueDate: dueDate)
                .onAppear { title = "" }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var defaultReminder: Date {
        Calendar.app.date(byAdding: .hour, value: 1, to: .now) ?? .now
    }

    private func save() {
        let text = trimmedTitle
        guard !text.isEmpty else { return }
        do {
            let (workspace, me) = try SeedService.ensureSeed(in: modelContext)
            let target = WorkspaceScope.creationTarget(raw: scopeRaw, workspaces: workspaces) ?? workspace
            let task = TodoTask(
                workspaceID: target.id,
                title: text,
                dueAt: dueDate,
                remindAt: remindEnabled ? remindDate : nil,
                createdByID: me.id
            )
            modelContext.insert(task)
            // D60: titolo ripulito, !priorità, /progetto, date nel testo, #tag.
            CaptureApplier.apply(
                text: text, to: task,
                selectedProject: selectedProject,
                suppressDate: suppressDate,
                suppressPriority: suppressPriority,
                in: modelContext
            )
            try modelContext.save()
            NotificationService.shared.sync(task: task)
            withAnimation(.dsQuick) { savedCount += 1 }
            title = ""
            selectedProject = nil
            suppressDate = false
            suppressPriority = false
            isTitleFocused = true
        } catch {
            reportFailure("Quick capture failed: \(error)")
        }
    }
}

#Preview {
    QuickCaptureView()
        .modelContainer(PreviewSampleData.make().container)
}
