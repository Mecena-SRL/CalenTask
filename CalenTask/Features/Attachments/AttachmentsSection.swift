import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(iOS)
import QuickLook
#endif

/// Allegati nello stesso ambiente del lavoro (D33): file locali con
/// "Apri con l'app predefinita" / "Mostra nel Finder", oppure link web.
/// Riusabile: per una task o per i documenti di progetto.
struct AttachmentsSection: View {
    @Environment(\.modelContext) private var modelContext
    let workspaceID: UUID
    var taskID: UUID? = nil
    var projectID: UUID? = nil
    var title = "Allegati"

    @Query(filter: #Predicate<Attachment> { $0.deletedAt == nil },
           sort: \Attachment.createdAt)
    private var allAttachments: [Attachment]

    @State private var showsImporter = false
    @State private var newLink = ""
    @State private var showsLinkField = false
    #if os(iOS)
    @State private var previewURL: URL?
    #endif

    private var attachments: [Attachment] {
        allAttachments.filter {
            if let taskID { return $0.taskID == taskID }
            if let projectID { return $0.projectID == projectID && $0.taskID == nil }
            return false
        }
    }

    var body: some View {
        Section(title) {
            ForEach(attachments, id: \.id) { attachment in
                row(attachment)
            }

            HStack(spacing: DS.l) {
                Button {
                    showsImporter = true
                } label: {
                    Label("File…", systemImage: "paperclip")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Button {
                    withAnimation(.dsQuick) { showsLinkField.toggle() }
                } label: {
                    Label("Link…", systemImage: "link.badge.plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .font(.dsMeta)

            if showsLinkField {
                HStack {
                    TextField("https://…", text: $newLink)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit(addLink)
                    Button("Aggiungi", action: addLink)
                        .disabled(URL(string: newLink)?.scheme == nil)
                }
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                if let attachment = Attachment.file(
                    url: url, workspaceID: workspaceID, taskID: taskID, projectID: projectID
                ) {
                    modelContext.insert(attachment)
                }
            }
        }
        #if os(iOS)
        .quickLookPreview($previewURL)
        #endif
    }

    private func row(_ attachment: Attachment) -> some View {
        HStack(spacing: DS.m) {
            DSIconTile(
                systemImage: attachment.isFile ? "doc.fill" : "link",
                tint: attachment.isFile ? .blue : .teal
            )
            Text(attachment.name)
                .font(.dsMeta)
                .lineLimit(1)
            Spacer()

            // "Apri con": il file si apre nel suo programma (D33).
            Button {
                open(attachment)
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Apri con l'app predefinita")

            #if os(macOS)
            if attachment.isFile {
                Button {
                    reveal(attachment)
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Mostra nel Finder")
            }
            #endif

            Button(role: .destructive) {
                withAnimation { attachment.deletedAt = .now; attachment.updatedAt = .now }
            } label: {
                Image(systemName: "trash")
                    .font(.dsCaption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

    private func addLink(){
        guard let url = URL(string: newLink.trimmingCharacters(in: .whitespaces)),
              url.scheme != nil
        else { return }
        modelContext.insert(Attachment(
            workspaceID: workspaceID, taskID: taskID, projectID: projectID,
            name: url.host() ?? url.absoluteString, urlString: url.absoluteString
        ))
        newLink = ""
        showsLinkField = false
    }

    private func open(_ attachment: Attachment) {
        if attachment.isFile {
            guard let url = attachment.resolvedFileURL() else { return }
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            previewURL = url   // Quick Look + "condividi/apri in" su iOS
            #endif
        } else if let url = attachment.urlString.flatMap(URL.init(string:)) {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
        }
    }

    #if os(macOS)
    private func reveal(_ attachment: Attachment) {
        guard let url = attachment.resolvedFileURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #endif
}
