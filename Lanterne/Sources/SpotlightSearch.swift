import AppKit
import LanterneCore

/// Longue traine : recherche Spotlight par nom (`NSMetadataQuery`, dossier personnel), lancee 150 ms apres la
/// derniere frappe, a partir de 2 caracteres. Les resultats arrivent par lots (200 au plus) ; la requete
/// s'arrete a la fin de la collecte, au bout de 2 s, ou a la frappe suivante. Une requete synchrone
/// (`MDQuery`) ne convient pas : sans acces a Documents, Bureau et Telechargements, Spotlight filtre ces
/// dossiers apres coup et une requete tres large ("a") peut durer plus de 40 s, sans pouvoir l'annuler.
@MainActor
final class SpotlightSearch {
    static let delay: Duration = .milliseconds(150)
    static let deadline: Duration = .seconds(2)
    static let maxCount = 200

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var deadlineTask: Task<Void, Never>?

    /// Arrete la requete en cours (aucun rappel ne suivra).
    func cancel() {
        deadlineTask?.cancel()
        deadlineTask = nil
        query?.stop()
        query = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
    }

    /// `update` recoit les resultats a chaque lot, puis une derniere fois avec `finished` vrai.
    func search(_ text: String, update: @escaping @MainActor (_ items: [Item], _ finished: Bool) -> Void) {
        cancel()
        let q = NSMetadataQuery()
        let pattern = "*" + Self.escapeLike(text) + "*"
        q.predicate = NSPredicate(format: "%K LIKE[cd] %@ AND %K != %@", NSMetadataItemDisplayNameKey, pattern,
                                  NSMetadataItemContentTypeKey, "com.apple.application-bundle")
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.notificationBatchingInterval = 0.1
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let center = NotificationCenter.default
        let deliver: @MainActor (Bool) -> Void = { [weak self, weak q] finished in
            guard let self, let q, self.query === q else { return }
            q.disableUpdates()
            var items: [Item] = []
            for case let result as NSMetadataItem in q.results {
                if items.count >= Self.maxCount { break }
                if let item = RecentFiles.item(result, home: home) { items.append(item) }
            }
            q.enableUpdates()
            if finished { self.cancel() }
            update(items, finished)
        }
        observers.append(center.addObserver(forName: .NSMetadataQueryGatheringProgress, object: q, queue: .main) { _ in
            MainActor.assumeIsolated { deliver(false) }
        })
        observers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { _ in
            MainActor.assumeIsolated { deliver(true) }
        })
        query = q
        q.start()
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: Self.deadline)
            guard !Task.isCancelled, let self, self.query === q else { return }
            deliver(true)
        }
    }

    /// Une recherche complete (sonde) : attend la fin de la collecte ou le delai.
    func run(_ text: String) async -> [Item] {
        await withCheckedContinuation { continuation in
            search(text) { items, finished in if finished { continuation.resume(returning: items) } }
        }
    }

    /// `*` et `?` sont des jokers de LIKE : on les echappe, comme la barre oblique inverse.
    nonisolated static func escapeLike(_ text: String) -> String {
        var out = ""
        for c in text {
            if c == "\\" || c == "*" || c == "?" { out.append("\\") }
            out.append(c)
        }
        return out
    }
}
