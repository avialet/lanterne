import CoreServices
import Foundation
import LanterneCore
import os

/// Longue traine : recherche Spotlight par nom (`MDQuery`, 200 resultats au plus, dossier personnel),
/// lancee 150 ms apres la derniere frappe, a partir de 2 caracteres. Une recherche depassee n'est pas lancee,
/// et son resultat est ignore s'il arrive apres une frappe plus recente.
final class SpotlightSearch: Sendable {
    static let delay: Duration = .milliseconds(150)
    static let maxCount = 200

    private let queue = DispatchQueue(label: "fr.vialet.lanterne.spotlight", qos: .userInitiated)
    private let generation = OSAllocatedUnfairLock(initialState: 0)

    /// Annule les recherches en cours (leur resultat sera ignore).
    func cancel() { generation.withLock { $0 += 1 } }

    @MainActor
    func search(_ text: String, completion: @escaping @MainActor @Sendable ([Item]) -> Void) {
        let token = generation.withLock { value -> Int in value += 1; return value }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        queue.async { [generation] in
            guard generation.withLock({ $0 }) == token else { return }
            let items = Self.run(text, home: home)
            DispatchQueue.main.async {
                guard generation.withLock({ $0 }) == token else { return }
                MainActor.assumeIsolated { completion(items) }
            }
        }
    }

    /// Requete synchrone (hors fil principal).
    static func run(_ text: String, home: String) -> [Item] {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "*", with: "\\*")
        let string = "kMDItemDisplayName == \"*\(escaped)*\"cd && kMDItemContentType != \"com.apple.application-bundle\""
        guard let query = MDQueryCreate(kCFAllocatorDefault, string as CFString, nil, nil) else { return [] }
        MDQuerySetMaxCount(query, maxCount)
        MDQuerySetSearchScope(query, [home] as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var items: [Item] = []
        for i in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, i) else { continue }
            let item = unsafeBitCast(raw, to: MDItem.self)
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String, !path.contains(".app/") else { continue }
            let type = MDItemCopyAttribute(item, kMDItemContentType) as? String ?? ""
            let folder = type == "public.folder"
            let name = folder ? (MDItemCopyAttribute(item, kMDItemDisplayName) as? String ?? (path as NSString).lastPathComponent)
                : (path as NSString).lastPathComponent
            let last = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            items.append(Item(key: Item.fileKey(path), title: name,
                              subtitle: RecentFiles.abbreviate((path as NSString).deletingLastPathComponent, home: home),
                              kind: folder ? .folder : .file, target: path, lastUsed: last))
        }
        return items
    }
}
