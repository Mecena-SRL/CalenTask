import Foundation

struct ProjectTemplate: Identifiable {
    let id: String
    let name: String
    let category: TemplateCategory
    let summary: String
    let suggestedColorHex: String
    let phases: [PhaseTemplate]
    /// Custom workflow pipeline (D29): ordered stage names; the last one is
    /// terminal. Empty ⇒ the project uses plain statuses.
    var stages: [String] = []
}

struct PhaseTemplate {
    let name: String
    /// Standard lavorazioni, pre-created as deletable starter tasks.
    let starterTasks: [String]
}

enum TemplateCategory: String, CaseIterable, Identifiable {
    case cinema, business, vuoto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cinema: "Cinema"
        case .business: "Business"
        case .vuoto: "Da zero"
        }
    }
}

enum TemplateCatalog {
    static let all: [ProjectTemplate] = [
        concert, documentary, musicVideo,
        feature, short, commercial,
        generic, productLaunch, grant, empty,
    ]

    static func templates(in category: TemplateCategory) -> [ProjectTemplate] {
        all.filter { $0.category == category }
    }

    // MARK: Mécena (D30) — template con pipeline di lavorazione

    static let concert = ProjectTemplate(
        id: "mecena.concert",
        name: "Concerto multicam",
        category: .cinema,
        summary: "Dal preventivo all'archivio: il flusso completo di una ripresa concerto.",
        suggestedColorHex: "#7C3AED",
        phases: [
            PhaseTemplate(name: "Pre-produzione", starterTasks: [
                "Preventivo e offerta",
                "Conferma e contratto",
                "Scheda tecnica (input audio, scaletta, luci)",
                "Convocazione troupe",
                "Noleggi camere e ottiche",
                "Sopralluogo venue",
            ]),
            PhaseTemplate(name: "Riprese", starterTasks: [
                "Setup multicam e posizioni",
                "Linea audio dal mixer di sala",
                "Riprese concerto",
            ]),
            PhaseTemplate(name: "Post-produzione", starterTasks: [
                "Ingest e backup doppia copia",
                "Sync multicam (audio di riferimento)",
                "Montaggio integrale",
                "Color e grafiche titoli",
                "Export master",
                "Estratti social (reel e teaser)",
            ]),
            PhaseTemplate(name: "Chiusura", starterTasks: [
                "Consegna cliente e approvazione",
                "Fattura",
                "Archivio progetto (LTO/NAS)",
            ]),
        ],
        stages: [
            "Preventivo", "Conferma", "Scheda tecnica", "Troupe", "Riprese",
            "Ingest", "Sync", "Montaggio integrale", "Export",
            "Estratti social", "Fattura", "Archivio",
        ]
    )

    static let documentary = ProjectTemplate(
        id: "mecena.documentary",
        name: "Documentario",
        category: .cinema,
        summary: "Dallo sviluppo alla distribuzione festival, trascrizioni incluse.",
        suggestedColorHex: "#0E7490",
        phases: [
            PhaseTemplate(name: "Sviluppo e ricerca", starterTasks: [
                "Soggetto e trattamento",
                "Ricerca archivi e materiali",
                "Finanziamenti e bandi",
                "Liberatorie e permessi",
            ]),
            PhaseTemplate(name: "Pre-produzione", starterTasks: [
                "Interviste da fissare",
                "Location e sopralluoghi",
                "Piano riprese",
            ]),
            PhaseTemplate(name: "Riprese", starterTasks: [
                "Riprese principali",
                "Backup giornalieri doppia copia",
            ]),
            PhaseTemplate(name: "Post-produzione", starterTasks: [
                "Trascrizioni interviste",
                "Selezione materiale",
                "Montaggio",
                "Revisioni",
                "Color e mix audio",
                "Sottotitoli e accessibilità",
            ]),
            PhaseTemplate(name: "Distribuzione", starterTasks: [
                "Strategia festival",
                "Iscrizioni festival",
                "Materiali promozionali",
            ]),
        ],
        stages: [
            "Sviluppo", "Ricerca", "Pre-produzione", "Riprese", "Backup",
            "Trascrizioni", "Montaggio", "Revisioni", "Color/Audio",
            "Sottotitoli", "Festival/Distribuzione",
        ]
    )

    static let musicVideo = ProjectTemplate(
        id: "mecena.musicvideo",
        name: "Videoclip",
        category: .cinema,
        summary: "Dal brief dell'artista alla delivery social e master.",
        suggestedColorHex: "#DB2777",
        phases: [
            PhaseTemplate(name: "Creatività", starterTasks: [
                "Brief artista",
                "Concept e trattamento",
                "Moodboard",
                "Preventivo e approvazione",
            ]),
            PhaseTemplate(name: "Produzione", starterTasks: [
                "Piano di produzione",
                "Casting e location",
                "Riprese",
            ]),
            PhaseTemplate(name: "Post-produzione", starterTasks: [
                "Rough cut",
                "Revisioni artista/label",
                "Final cut",
                "Color",
                "Delivery social e master",
            ]),
        ],
        stages: [
            "Brief artista", "Concept", "Preventivo", "Moodboard",
            "Piano produzione", "Riprese", "Rough cut", "Final cut",
            "Color", "Delivery",
        ]
    )

    // MARK: Cinema

    static let feature = ProjectTemplate(
        id: "cinema.feature",
        name: "Produzione cinematografica (lungometraggio)",
        category: .cinema,
        summary: "Dallo sviluppo alla distribuzione, con le lavorazioni standard di ogni fase.",
        suggestedColorHex: "#0E7490",
        phases: [
            PhaseTemplate(name: "Sviluppo", starterTasks: [
                "Soggetto e trattamento",
                "Sceneggiatura (stesure)",
                "Opzione / acquisizione diritti",
                "Budget preliminare",
                "Ricerca finanziamenti (fondi, tax credit, coproduzioni)",
                "Casting preliminare / lettere d'intenti",
                "Piano di produzione preliminare",
            ]),
            PhaseTemplate(name: "Pre-produzione", starterTasks: [
                "Spoglio della sceneggiatura",
                "Piano di lavorazione",
                "Casting e contratti artistici",
                "Sopralluoghi e location scouting",
                "Permessi e occupazioni suolo",
                "Formazione della troupe",
                "Scenografia e attrezzeria",
                "Costumi",
                "Trucco e parrucco",
                "Shot list / storyboard",
                "Noleggio attrezzatura (camera, luci, audio)",
                "Assicurazioni",
                "Prove con gli attori",
            ]),
            PhaseTemplate(name: "Riprese", starterTasks: [
                "Ordini del giorno",
                "Riprese principali",
                "Gestione giornalieri (dailies) e backup DIT",
                "Foto di scena e backstage",
                "Edizione (continuità)",
                "Riprese aggiuntive / pick-up",
            ]),
            PhaseTemplate(name: "Post-produzione", starterTasks: [
                "Montaggio (assembly → rough cut → fine cut → picture lock)",
                "Montaggio del suono",
                "ADR / doppiaggio",
                "Musiche originali e diritti musicali",
                "Mix audio",
                "Color correction e grading",
                "VFX e clean-up",
                "Titoli di testa/coda e grafica",
                "Master e DCP",
                "Sottotitoli e accessibilità",
            ]),
            PhaseTemplate(name: "Distribuzione e promozione", starterTasks: [
                "Strategia festival e iscrizioni",
                "Vendite e distribuzione (sala / piattaforme)",
                "Trailer e poster",
                "Press kit e ufficio stampa",
                "Anteprima / première",
                "Uscita e monitoraggio",
                "Adempimenti e depositi (DGCA, SIAE)",
            ]),
        ]
    )

    static let short = ProjectTemplate(
        id: "cinema.short",
        name: "Cortometraggio",
        category: .cinema,
        summary: "Il flusso del lungometraggio, condensato per un corto.",
        suggestedColorHex: "#7C3AED",
        phases: [
            PhaseTemplate(name: "Sviluppo", starterTasks: [
                "Soggetto e sceneggiatura",
                "Budget",
                "Finanziamenti / bandi",
            ]),
            PhaseTemplate(name: "Pre-produzione", starterTasks: [
                "Casting",
                "Location e permessi",
                "Troupe e attrezzatura",
                "Piano di lavorazione",
            ]),
            PhaseTemplate(name: "Riprese", starterTasks: [
                "Ordini del giorno",
                "Riprese",
                "Backup giornalieri",
            ]),
            PhaseTemplate(name: "Post-produzione", starterTasks: [
                "Montaggio",
                "Suono e mix",
                "Color",
                "Master / DCP",
            ]),
            PhaseTemplate(name: "Festival e distribuzione", starterTasks: [
                "Iscrizioni festival",
                "Materiali promozionali",
            ]),
        ]
    )

    static let commercial = ProjectTemplate(
        id: "cinema.commercial",
        name: "Video commerciale / Spot",
        category: .cinema,
        summary: "Lavoro su commissione: dal brief del cliente alla consegna.",
        suggestedColorHex: "#D97706",
        phases: [
            PhaseTemplate(name: "Brief e concept", starterTasks: [
                "Brief cliente",
                "Concept e script",
                "Preventivo e approvazione",
            ]),
            PhaseTemplate(name: "Pre-produzione", starterTasks: [
                "Casting / location",
                "Shot list",
                "Call sheet",
            ]),
            PhaseTemplate(name: "Riprese", starterTasks: [
                "Shooting",
            ]),
            PhaseTemplate(name: "Post-produzione", starterTasks: [
                "Montaggio",
                "Color e grafica",
                "Revisioni cliente",
            ]),
            PhaseTemplate(name: "Consegna", starterTasks: [
                "Export nei formati richiesti",
                "Consegna e fatturazione",
            ]),
        ]
    )

    // MARK: Business

    static let generic = ProjectTemplate(
        id: "business.generic",
        name: "Progetto generico",
        category: .business,
        summary: "Pianifica, esegui, verifica, chiudi.",
        suggestedColorHex: "#475569",
        phases: [
            PhaseTemplate(name: "Pianificazione", starterTasks: [
                "Obiettivi e ambito",
                "Attività e tempi",
                "Budget",
            ]),
            PhaseTemplate(name: "Esecuzione", starterTasks: [
                "Avanzamento",
                "Riunioni di stato",
            ]),
            PhaseTemplate(name: "Revisione", starterTasks: [
                "Verifica risultati",
                "Correzioni",
            ]),
            PhaseTemplate(name: "Chiusura", starterTasks: [
                "Consegna",
                "Retrospettiva",
            ]),
        ]
    )

    static let productLaunch = ProjectTemplate(
        id: "business.launch",
        name: "Lancio prodotto / servizio",
        category: .business,
        summary: "Dalla ricerca di mercato al follow-up post lancio.",
        suggestedColorHex: "#0F766E",
        phases: [
            PhaseTemplate(name: "Ricerca e strategia", starterTasks: [
                "Analisi mercato",
                "Posizionamento",
                "Pricing",
            ]),
            PhaseTemplate(name: "Sviluppo", starterTasks: [
                "Realizzazione",
                "Test",
            ]),
            PhaseTemplate(name: "Marketing", starterTasks: [
                "Piano comunicazione",
                "Materiali",
                "Campagne",
            ]),
            PhaseTemplate(name: "Lancio", starterTasks: [
                "Go-live",
                "Monitoraggio",
            ]),
            PhaseTemplate(name: "Follow-up", starterTasks: [
                "Feedback",
                "Iterazione",
            ]),
        ]
    )

    static let grant = ProjectTemplate(
        id: "business.grant",
        name: "Bando / Finanziamento",
        category: .business,
        summary: "Dalla ricerca del bando alla rendicontazione finale.",
        suggestedColorHex: "#B45309",
        phases: [
            PhaseTemplate(name: "Ricerca e valutazione", starterTasks: [
                "Monitoraggio bandi",
                "Verifica requisiti",
            ]),
            PhaseTemplate(name: "Preparazione", starterTasks: [
                "Documentazione amministrativa",
                "Progetto e budget",
                "Lettere e partnership",
            ]),
            PhaseTemplate(name: "Presentazione", starterTasks: [
                "Caricamento / invio",
                "Conferma di ricezione",
            ]),
            PhaseTemplate(name: "Esito e rendicontazione", starterTasks: [
                "Comunicazioni esito",
                "Rendicontazione spese",
                "Relazione finale",
            ]),
        ]
    )

    // MARK: Vuoto

    static let empty = ProjectTemplate(
        id: "vuoto.empty",
        name: "Progetto vuoto",
        category: .vuoto,
        summary: "Nessuna fase predefinita: parti da un foglio bianco.",
        suggestedColorHex: "#0E7490",
        phases: []
    )
}
