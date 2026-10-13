import Foundation
import LanterneCore

/// Actions rapides des autres apps vialet.app (fiches `HubManifest` ecrites pour Vialet) : "dicter" trouve
/// `chuchote://dicter`. Fiches non fiables : schema de l'app elle-meme et identifiants verifies
/// (VialetActionLink), app presente.
enum VialetActions {
    static func load(excluding own: String) -> (items: [Item], appPaths: [String: String]) {
        var items: [Item] = []
        var paths: [String: String] = [:]
        for manifest in HubManifest.loadAll(from: HubManifest.directory) where manifest.bundleIdentifier != own {
            guard manifest.appPath.hasSuffix(".app"), FileManager.default.fileExists(atPath: manifest.appPath) else { continue }
            for action in manifest.actions {
                guard let url = VialetActionLink.url(bundleIdentifier: manifest.bundleIdentifier, scheme: manifest.scheme,
                                                     actionId: action.id) else { continue }
                let key = Item.actionKey(bundle: manifest.bundleIdentifier, id: action.id)
                items.append(Item(key: key, title: action.title, subtitle: manifest.displayName,
                                  keywords: [manifest.displayName, action.id], kind: .action, target: url.absoluteString))
                paths[key] = manifest.appPath
            }
        }
        return (items, paths)
    }
}
