# CalenTask — regole del progetto

App SwiftUI multipiattaforma (iOS / iPadOS / macOS 26) con SwiftData + CloudKit
(database privato `iCloud.it.mecena.CalenTask`), widget WidgetKit (App Group
`group.it.mecena.CalenTask`) e sync EventKit. Lingua di UI e commenti: italiano.

Roadmap e priorità: issue "Roadmap" su GitHub (etichette `P0`…`P3`, `fase-0`…`fase-4`).

## Struttura

- `CalenTask/App` — entry point, shell, router, sidebar.
- `CalenTask/Models` — modelli `@Model` + `CalenTaskSchema.swift` (registro versioni).
- `CalenTask/Services` — sync calendario, notifiche, automazioni, seed, template.
- `CalenTask/Features/<Area>` — schermate per area funzionale.
- `CalenTask/DesignSystem` — token (`DS`, `DSColor`, …) e componenti riusabili.
- `CalenTask/Support` — parser, estensioni, bridge widget, dati di preview.
- `Widget/` — estensione widget (legge lo snapshot JSON scritto da `WidgetBridge`).

Il target usa cartelle sincronizzate (`PBXFileSystemSynchronizedRootGroup`): ogni
file dentro `CalenTask/` entra nel bundle. Non metterci artefatti generati
(`graphify-out/` è escluso e ignorato da git).

## Schema SwiftData / CloudKit (vincolante)

1. Solo modifiche **additive**: nuove proprietà opzionali o con default. Mai
   rinominare/eliminare/cambiare tipo (rinomina dello storage solo con
   `originalName`).
2. Ogni modifica al modello = nuova `CalenTaskSchemaVn` in
   `Models/CalenTaskSchema.swift` come registro, e `CalenTaskApp` punta
   all'ultima. La migrazione è automatica (lightweight): niente
   `SchemaMigrationPlan` (le versioni condividono le stesse classi → checksum
   duplicati → crash).
3. Niente `@Attribute(.unique)`. Relazioni sempre opzionali: storage
   `...Storage: [T]? = []` + bridge calcolato non-optional.
4. Cancellazione = soft delete (`deletedAt`); ogni query filtra `deletedAt == nil`.

## Convenzioni di dominio

- **Funnel delle mutazioni**: ogni modifica a una `TodoTask` passa da
  `TodoTask+Mutations.swift` (`setStatus`, `setDue`, `move`, `softDelete`, …)
  o termina con `touch()`, che aggiorna `updatedAt`, notifiche ed EventKit.
  Non chiamare `touch()` se nulla è cambiato.
- **Spazio di destinazione** delle nuove task/progetti:
  `WorkspaceScope.creationTarget(raw:workspaces:)` — mai lo spazio "corrente"
  di `SeedService`.
- Predicati riusabili: `TodoTask.openPredicate`, `TodoTask.inboxPredicate`.
  Preferire predicati filtrati nello store a filtri in memoria su tutte le task.
- Calendario: usare `Calendar.app` (settimana da lunedì) nelle viste calendario.

## Build e test

- Xcode 26+, schema `CalenTask`. Test con Swift Testing in `CalenTaskTests`.
- CI: `.github/workflows/ci.yml` (build iOS Simulator + test macOS, senza firma).
- Da riga di comando:
  `xcodebuild test -project CalenTask.xcodeproj -scheme CalenTask -destination 'platform=macOS' -only-testing:CalenTaskTests CODE_SIGNING_ALLOWED=NO`
