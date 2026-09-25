import Foundation
import Observation
import Security
#if os(macOS)
import AppKit
#endif

// MARK: Release di GitHub

/// Una release come la restituisce l'API di GitHub (solo i campi usati).
nonisolated struct GitHubRelease: Decodable, Equatable, Sendable {
    nonisolated struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let size: Int
        /// URL dell'API: con un token scarica anche dai repository privati.
        let url: URL
        let browserDownloadURL: URL

        nonisolated enum CodingKeys: String, CodingKey {
            case name, size, url
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let htmlURL: URL
    let assets: [Asset]

    nonisolated enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, draft, prerelease, assets
        case htmlURL = "html_url"
    }
}

/// Un aggiornamento disponibile: la release più recente con un DMG.
nonisolated struct AppUpdate: Equatable, Sendable {
    let version: String
    let title: String
    let notes: String
    let isPrerelease: Bool
    let pageURL: URL
    let asset: GitHubRelease.Asset
}

nonisolated enum UpdateMath {
    /// "v0.1.10" → [0, 1, 10]. Suffissi non numerici ignorati ("1.2-beta" → [1, 2]).
    static func components(_ version: String) -> [Int] {
        let trimmed = version.hasPrefix("v") || version.hasPrefix("V")
            ? String(version.dropFirst()) : version
        return trimmed.split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }

    /// Confronto numerico, componente per componente ("0.1.10" > "0.1.9").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// La release più recente più nuova della versione installata, con un
    /// DMG allegato. Bozze escluse; pre-release solo se richieste.
    static func latestUpdate(
        in releases: [GitHubRelease], includePrereleases: Bool, currentVersion: String
    ) -> AppUpdate? {
        releases
            .filter { !$0.draft && (includePrereleases || !$0.prerelease) }
            .filter { isNewer($0.tagName, than: currentVersion) }
            .compactMap { release -> AppUpdate? in
                guard let dmg = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
                else { return nil }
                let version = release.tagName.hasPrefix("v")
                    ? String(release.tagName.dropFirst()) : release.tagName
                return AppUpdate(
                    version: version,
                    title: release.name ?? release.tagName,
                    notes: release.body ?? "",
                    isPrerelease: release.prerelease,
                    pageURL: release.htmlURL,
                    asset: dmg
                )
            }
            .max { isNewer($1.version, than: $0.version) }
    }
}

// MARK: Token (Portachiavi)

/// Il token GitHub per il repository privato: nel Portachiavi, mai nelle
/// preferenze.
nonisolated enum GitHubTokenStore {
    private static let service = "it.mecena.CalenTask.github"
    private static let account = "releases"
    /// C'è un token salvato (per l'interfaccia, senza leggere il Portachiavi).
    static let savedFlagKey = "updates.hasGitHubToken"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty
        else { return nil }
        return token
    }

    static func save(_ token: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var saved = false
        if !trimmed.isEmpty {
            var attributes = base
            attributes[kSecValueData as String] = Data(trimmed.utf8)
            saved = SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        }
        UserDefaults.standard.set(saved, forKey: savedFlagKey)
    }
}

// MARK: Servizio

/// Controlla le release di GitHub e installa il DMG più recente.
///
/// Su Mac, senza sandbox (le build DMG), sostituisce l'app al suo posto e la
/// riavvia; altrimenti apre il DMG da trascinare in Applicazioni.
@Observable @MainActor
final class UpdateService {
    static let shared = UpdateService()
    static let includePrereleasesKey = "updates.includePrereleases"

    static let repository = "Mecena-SRL/CalenTask"

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppUpdate)
        case downloading(AppUpdate)
        case installing(AppUpdate)
        /// Il DMG è scaricato e aperto: va trascinato a mano.
        case manualInstall(URL)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var lastCheckAt: Date?

    private init() {}

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    func checkForUpdates(includePrereleases: Bool) async {
        guard !isBusy else { return }
        phase = .checking
        do {
            var request = URLRequest(
                url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases?per_page=30")!
            )
            Self.authorize(&request)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validate(response)
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            lastCheckAt = .now
            if let update = UpdateMath.latestUpdate(
                in: releases, includePrereleases: includePrereleases,
                currentVersion: Self.currentVersion
            ) {
                phase = .available(update)
            } else {
                phase = .upToDate
            }
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    #if os(macOS)
    func install(_ update: AppUpdate) async {
        guard !isBusy else { return }
        phase = .downloading(update)
        do {
            let dmg = try await download(update)
            phase = .installing(update)
            let appURL = Bundle.main.bundleURL
            let canReplace = !Self.isSandboxed
                && FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path)
                && appURL.pathExtension == "app"
            guard canReplace else {
                NSWorkspace.shared.open(dmg)
                phase = .manualInstall(dmg)
                return
            }
            try await Task.detached(priority: .userInitiated) {
                try UpdateInstaller.replaceApp(at: appURL, withAppInside: dmg)
            }.value
            UpdateInstaller.relaunch(appURL)
            NSApp.terminate(nil)
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    /// Scarica il DMG nella cartella Download (una copia resta lì).
    private func download(_ update: AppUpdate) async throws -> URL {
        var request = URLRequest(url: update.asset.url)
        Self.authorize(&request)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: .default, delegate: GitHubRedirectDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (temporary, response) = try await session.download(for: request)
        try Self.validate(response)

        let folder = (try? FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        let destination = folder.appendingPathComponent(update.asset.name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
    #endif

    private static func authorize(_ request: inout URLRequest) {
        if let token = GitHubTokenStore.read() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CalenTask/\(currentVersion)", forHTTPHeaderField: "User-Agent")
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw UpdateError.unauthorized
        case 403: throw UpdateError.forbidden
        case 404: throw UpdateError.notFound
        default: throw UpdateError.http(http.statusCode)
        }
    }

    private static func message(for error: Error) -> String {
        if let updateError = error as? UpdateError { return updateError.message }
        return error.localizedDescription
    }
}

nonisolated enum UpdateError: Error {
    case unauthorized, forbidden, notFound, http(Int)
    case mountFailed, appNotFound, commandFailed(String)

    var message: String {
        switch self {
        case .unauthorized: "Token GitHub non valido o scaduto."
        case .forbidden: "GitHub ha rifiutato la richiesta (limite di richieste o permessi del token)."
        case .notFound: "Repository non trovato: è privato, serve un token GitHub con accesso in lettura."
        case .http(let code): "GitHub ha risposto con errore \(code)."
        case .mountFailed: "Impossibile aprire il DMG scaricato."
        case .appNotFound: "Nel DMG non c'è CalenTask.app."
        case .commandFailed(let detail): "Installazione non riuscita: \(detail)"
        }
    }
}

/// Gli asset dei repository privati rimandano a un URL firmato: il token
/// NON va inoltrato fuori da GitHub (lo storage rifiuterebbe la richiesta).
nonisolated final class GitHubRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        var redirected = request
        if redirected.url?.host != "api.github.com" {
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return redirected
    }
}

#if os(macOS)
/// Monta il DMG, copia la nuova app al posto di quella in uso, smonta.
nonisolated enum UpdateInstaller {
    static func replaceApp(at appURL: URL, withAppInside dmg: URL) throws {
        let mountPoint = try attach(dmg)
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet", "-force"]) }

        let contents = try FileManager.default.contentsOfDirectory(
            at: mountPoint, includingPropertiesForKeys: nil
        )
        guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.appNotFound
        }
        let staged = appURL.deletingLastPathComponent()
            .appendingPathComponent(".CalenTask-update-\(UUID().uuidString).app")
        _ = try run("/usr/bin/ditto", [newApp.path, staged.path])
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        do {
            _ = try FileManager.default.replaceItemAt(appURL, withItemAt: staged)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }

    /// Riapre l'app appena questa istanza è uscita.
    static func relaunch(_ appURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", appURL.path]
        try? process.run()
    }

    private static func attach(_ dmg: URL) throws -> URL {
        let output = try run("/usr/bin/hdiutil", [
            "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-plist",
        ])
        guard let plist = try PropertyListSerialization.propertyList(from: output, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mount = entities.compactMap({ $0["mount-point"] as? String }).first
        else { throw UpdateError.mountFailed }
        return URL(fileURLWithPath: mount)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.commandFailed(detail.isEmpty ? (tool as NSString).lastPathComponent : detail)
        }
        return data
    }
}
#endif
