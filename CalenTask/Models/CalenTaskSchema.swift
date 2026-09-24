import Foundation
import SwiftData

// MARK: Salvataggio a prova di aggiornamenti (D45-bis, rivisto v7)
//
// Lo schema resta VERSIONATO come registro storico, ma la migrazione è
// AUTOMATICA (lightweight): niente più SchemaMigrationPlan.
//
// Perché (fix v7, 2026-06-11): gli enum versione qui sotto puntano tutti
// alle STESSE classi vive, quindi due versioni qualunque hanno checksum
// identici → un MigrationStage tra loro fa crashare Core Data all'avvio
// ("Duplicate version checksums detected") appena uno store esistente va
// migrato. Inoltre CloudKit supporta SOLO la migrazione lightweight.
//
// Regole (vincolanti, vedi CLAUDE.md):
//   1. Con CloudKit le modifiche devono essere ADDITIVE: nuove proprietà
//      opzionali o con default, mai rinominare/eliminare/cambiare tipo
//      (rinominare lo storage è ammesso SOLO con `originalName`).
//   2. Ogni modifica al modello = nuova `CalenTaskSchemaVn` QUI come
//      registro di cosa è cambiato; la migrazione la fa il sistema.
//   3. Niente @Attribute(.unique), relazioni e proprietà opzionali o con
//      default (requisiti CloudKit). Le relazioni: storage opzionale
//      `...Storage` + bridge calcolato non-optional.

enum CalenTaskSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Workspace.self,
            Membership.self,
            UserProfile.self,
            Project.self,
            TodoTask.self,
            TaskDependency.self,
            Tag.self,
            CustomFieldDefinition.self,
            CustomFieldValue.self,
            SavedView.self,
            WorkflowStage.self,
            AutomationRule.self,
            Attachment.self,
        ]
    }
}

/// V2 (v6 S3 — produzione video): aggiunge Contact, CrewAssignment e
/// ProductionScene. Solo aggiunte: nessun modello esistente è cambiato.
enum CalenTaskSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Workspace.self,
            Membership.self,
            UserProfile.self,
            Project.self,
            TodoTask.self,
            TaskDependency.self,
            Tag.self,
            CustomFieldDefinition.self,
            CustomFieldValue.self,
            SavedView.self,
            WorkflowStage.self,
            AutomationRule.self,
            Attachment.self,
            Contact.self,
            CrewAssignment.self,
            ProductionScene.self,
        ]
    }
}

/// V3 (v6 S3.5): aggiunge `TodoTask.colorHex` (colore proprio delle fasi,
/// vuoto = colore del progetto). Solo una proprietà nuova con default.
enum CalenTaskSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        CalenTaskSchemaV2.models
    }
}

/// V4 (v6 S5): aggiunge `TodoTask.travelMinutes` (tempo di viaggio per gli
/// eventi con luogo → avviso "Parti ora"). Solo una proprietà con default.
enum CalenTaskSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        CalenTaskSchemaV2.models
    }
}

/// V5 (v7 CRM-1, D72): aggiunge `Contact.contactIdentifier` (legame con
/// Apple Contacts). In più (fix v7): le relazioni tasks/subtasks/tags
/// diventano storage opzionali (`...Storage`, originalName) perché
/// CloudKit esige relazioni opzionali — prima il database CloudKit non
/// si caricava MAI e l'app ripiegava in silenzio sullo store locale.
enum CalenTaskSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        CalenTaskSchemaV2.models
    }
}

/// V6 (v7, D75): aggiunge `Project.isFavorite` (preferiti in sidebar e
/// Sfoglia). Solo una proprietà nuova con default.
enum CalenTaskSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        CalenTaskSchemaV2.models
    }
}

/// V7 (v8, F15/F39): aggiunge `TodoTask.completedAt` (timestamp di
/// completamento per il grafico Andamento) e `Project.productionEnabled`
/// (Scene opt-in per progetto). Solo proprietà opzionali/con default.
enum CalenTaskSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    static var models: [any PersistentModel.Type] {
        CalenTaskSchemaV2.models
    }
}

/// V8 (v8, G13): aggiunge `Project.parentProject` + `subprojectsStorage`
/// (gerarchia di progetti, max 5 generazioni). Relazioni opzionali nuove.
enum CalenTaskSchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

    static var models: [any PersistentModel.Type] {
        CalenTaskSchemaV2.models
    }
}

/// V9 (v8 Inbox provenienza): aggiunge a `TodoTask` la provenienza strutturata
/// (`sourceRaw`) e i dati del richiedente (`requesterName`, `requesterContact`,
/// `requestTypeLabel`) per chiarire da dove arriva ogni task in Inbox. Solo
/// proprietà nuove con default.
enum CalenTaskSchemaV9: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }

    static var models: [any PersistentModel.Type] {
        CalenTaskSchemaV2.models
    }
}

/// V10 (audit account A1, 2026-09-10): aggiunge `UserProfile.isLocalSeed`,
/// che marca il profilo "me" auto-generato al primo avvio (distinto da un
/// compagno di team aggiunto a mano) così la dedupe multi-dispositivo
/// (`SeedService.dedupeAfterCloudMerge`) non fonde più persone omonime.
/// Solo una proprietà nuova con default.
enum CalenTaskSchemaV10: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(10, 0, 0) }

    static var models: [any PersistentModel.Type] {
        CalenTaskSchemaV2.models
    }
}
