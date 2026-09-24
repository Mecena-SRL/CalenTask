import Foundation
import SwiftData

// Maps to future Supabase table `attachments` (D33).
// Documents live with the work: a file on disk (bookmark survives renames
// and moves) or a web link, attached to a task or to the whole project.
@Model
final class Attachment {
    var id: UUID = UUID()
    var workspaceID: UUID = UUID()
    var taskID: UUID?
    var projectID: UUID?
    var name: String = ""
    /// File attachments: security-scoped bookmark to the local file.
    var bookmarkData: Data?
    /// Link attachments: plain URL string (https, file server, Drive…).
    var urlString: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var isFile: Bool { bookmarkData != nil }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        taskID: UUID? = nil,
        projectID: UUID? = nil,
        name: String,
        bookmarkData: Data? = nil,
        urlString: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.taskID = taskID
        self.projectID = projectID
        self.name = name
        self.bookmarkData = bookmarkData
        self.urlString = urlString
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    // MARK: Bookmark plumbing

    /// Creates a file attachment from a picked URL (fileImporter).
    static func file(
        url: URL, workspaceID: UUID, taskID: UUID? = nil, projectID: UUID? = nil
    ) -> Attachment? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data?
        #if os(macOS)
        data = (try? url.bookmarkData(options: .withSecurityScope))
            ?? (try? url.bookmarkData())
        #else
        data = try? url.bookmarkData()
        #endif
        guard let data else { return nil }
        return Attachment(
            workspaceID: workspaceID, taskID: taskID, projectID: projectID,
            name: url.lastPathComponent, bookmarkData: data
        )
    }

    /// Resolves the bookmark back to a usable URL (refreshing it if stale).
    func resolvedFileURL() -> URL? {
        guard let bookmarkData else { return urlString.flatMap(URL.init(string:)) }
        var stale = false
        #if os(macOS)
        let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            bookmarkDataIsStale: &stale
        )
        #else
        let url = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &stale)
        #endif
        if stale, let url {
            #if os(macOS)
            self.bookmarkData = (try? url.bookmarkData(options: .withSecurityScope)) ?? bookmarkData
            #else
            self.bookmarkData = (try? url.bookmarkData()) ?? bookmarkData
            #endif
        }
        return url
    }
}
