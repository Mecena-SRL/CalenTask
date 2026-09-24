import SwiftUI
import SwiftData

/// Risolve `AppDestination.project(id)` nel dettaglio vivo (D70): usato come
/// detail su Mac/iPad e come push dentro Sfoglia su iPhone. Niente più
/// `openProjectID`: l'UUID È la destinazione.
struct ProjectDestinationView: View {
    @Query private var projects: [Project]

    init(projectID: UUID) {
        _projects = Query(filter: #Predicate<Project> {
            $0.id == projectID && $0.deletedAt == nil
        })
    }

    var body: some View {
        if let project = projects.first {
            ProjectDetailView(project: project)
        } else {
            DSEmptyState(
                icon: "folder.badge.questionmark",
                title: "Progetto non trovato",
                subtitle: "Forse è stato eliminato o vive in un altro spazio."
            )
        }
    }
}

/// Risolve `AppDestination.tag(id)` nelle attività etichettate (F3).
struct TagDestinationView: View {
    @Query private var tags: [Tag]

    init(tagID: UUID) {
        _tags = Query(filter: #Predicate<Tag> {
            $0.id == tagID && $0.deletedAt == nil
        })
    }

    var body: some View {
        if let tag = tags.first {
            TaggedTasksView(tag: tag)
        } else {
            DSEmptyState(
                icon: "number",
                title: "Etichetta non trovata",
                subtitle: "Forse è stata eliminata."
            )
        }
    }
}

/// Risolve `AppDestination.smartList(id)` nella lista viva.
struct SmartListDestinationView: View {
    @Query private var savedViews: [SavedView]

    init(listID: UUID) {
        _savedViews = Query(filter: #Predicate<SavedView> {
            $0.id == listID && $0.deletedAt == nil
        })
    }

    var body: some View {
        if let savedView = savedViews.first {
            SmartListView(savedView: savedView)
        } else {
            DSEmptyState(
                icon: "bookmark.slash",
                title: "Lista non trovata",
                subtitle: "Forse è stata eliminata."
            )
        }
    }
}
