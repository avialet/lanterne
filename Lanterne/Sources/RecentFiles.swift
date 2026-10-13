import AppKit
import LanterneCore

/// Fichiers et dossiers ouverts ces 90 derniers jours dans le dossier personnel : requete Spotlight vivante
/// (`NSMetadataQuery`, `kMDItemLastUsedDate >= $time.today(-90)`), tenue a jour par Spotlight.
@MainActor
final class RecentFiles {
    static let days = 90
    static let maxItems = 3000

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private let onChange: @MainActor ([Item]) -> Void

    init(onChange: @escaping @MainActor ([Item]) -> Void) {
        self.onChange = onChange
    }

    var isRunning: Bool { query != nil }

    func start() {
        guard query == nil else { return }
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(fromMetadataQueryString: "kMDItemLastUsedDate >= $time.today(-\(Self.days))")
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        q.notificationBatchingInterval = 2
        let center = NotificationCenter.default
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.collect() }
            })
        }
        query = q
        q.start()
    }

    func stop() {
        query?.stop()
        query = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
    }

    private func collect() {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var items: [Item] = []
        for case let result as NSMetadataItem in q.results {
            guard items.count < Self.maxItems, let item = Self.item(result, home: home) else { continue }
            items.append(item)
        }
        onChange(items)
    }

    static func item(_ result: NSMetadataItem, home: String) -> Item? {
        guard let path = result.value(forAttribute: NSMetadataItemPathKey) as? String,
              !path.hasSuffix(".app"), !path.contains(".app/") else { return nil }
        let type = result.value(forAttribute: NSMetadataItemContentTypeKey) as? String ?? ""
        if type == "com.apple.application-bundle" { return nil }
        let name = result.value(forAttribute: NSMetadataItemDisplayNameKey) as? String ?? (path as NSString).lastPathComponent
        let folder = type == "public.folder"
        let last = result.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date
        let count = (result.value(forAttribute: "kMDItemUseCount") as? NSNumber)?.intValue ?? 0
        return Item(key: Item.fileKey(path), title: folder ? name : (path as NSString).lastPathComponent,
                    subtitle: abbreviate((path as NSString).deletingLastPathComponent, home: home),
                    kind: folder ? .folder : .file, target: path, lastUsed: last, useCount: count)
    }

    /// `~/Documents/Projets`
    nonisolated static func abbreviate(_ path: String, home: String) -> String {
        path == home ? "~" : (path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
    }
}
