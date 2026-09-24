# CalenTask

Calendario avanzato che riunisce in un solo posto calendario, attività, progetti,
documenti e team. App nativa SwiftUI per **iPhone, iPad e Mac**.

## Requisiti

- Xcode 26+ (iOS / iPadOS / macOS 26)
- Per la sync: account Apple Developer con capability **iCloud (CloudKit)**
  container `iCloud.it.mecena.CalenTask` e **App Group**
  `group.it.mecena.CalenTask` (condiviso con il widget)

Senza entitlement iCloud (simulatore, build non firmate) l'app usa uno store
locale: funziona tutto tranne la sync tra dispositivi.

## Avvio

1. Apri `CalenTask.xcodeproj` e seleziona lo schema `CalenTask`.
2. Imposta il tuo team in *Signing & Capabilities* (target app e widget).
3. Esegui su "My Mac" o su un simulatore/dispositivo iOS.

In debug, il menu **Debug › Genera 500 attività di prova** (macOS) popola
l'app per provare prestazioni e viste.

## Test

```sh
xcodebuild test -project CalenTask.xcodeproj -scheme CalenTask \
  -destination 'platform=macOS' -only-testing:CalenTaskTests CODE_SIGNING_ALLOWED=NO
```

La CI (`.github/workflows/ci.yml`) esegue i test su macOS e la build iOS a ogni PR.

## Struttura

| Cartella | Contenuto |
|---|---|
| `CalenTask/App` | entry point, shell, router, sidebar |
| `CalenTask/Models` | modelli SwiftData + registro versioni dello schema |
| `CalenTask/Services` | sync calendario (EventKit), notifiche, automazioni, seed, template |
| `CalenTask/Features` | schermate per area (Calendario, Progetti, Inbox, Dashboard, …) |
| `CalenTask/DesignSystem` | token e componenti UI riusabili |
| `CalenTask/Support` | parser date/cattura, estensioni, bridge widget |
| `Widget` | widget "Oggi" (legge lo snapshot scritto dall'app) |

Regole di sviluppo (schema CloudKit, funnel delle mutazioni, convenzioni):
[`CLAUDE.md`](CLAUDE.md). Piano di lavoro: issue **Roadmap** su GitHub.
