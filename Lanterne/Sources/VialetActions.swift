import Foundation
import LanterneCore

/// Actions rapides des autres apps vialet.app (fiches `HubManifest` ecrites pour Vialet) : « dicter » trouve
/// `chuchote://dicter`. Fiches non fiables : bundle `fr.vialet.*`, schema en minuscules ASCII, app presente.
enum VialetActions {
    static func load(excluding own: String) -> (items: [Item], appPaths: [String: String]) {
        var items: [Item] = []
        var paths: [String: String] = [:]
        for manifest in HubManifest.loadAll(from: HubManifest.directory) where manifest.bundleIdentifier != own {
            guard manifest.bundleIdentifier.hasPrefix("fr.vialet."), isSafeScheme(manifest.scheme),
                  manifest.appPath.hasSuffix(".app"), FileManager.default.fileExists(atPath: manifest.appPath) else { continue }
            for action in manifest.actions {
                let key = Item.actionKey(bundle: manifest.bundleIdentifier, id: action.id)
                items.append(Item(key: key, title: action.title, subtitle: manifest.displayName,
                                  keywords: [manifest.displayName, action.id], kind: .action,
                                  target: "\(manifest.scheme)://\(action.id)"))
                paths[key] = manifest.appPath
            }
        }
        return (items, paths)
    }

    static func isSafeScheme(_ scheme: String) -> Bool {
        !scheme.isEmpty && scheme.count <= 30 && scheme.first!.isLetter
            && scheme.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
            && !["http", "https", "file", "ftp", "mailto", "javascript", "data", "ssh", "smb", "afp", "vnc"].contains(scheme)
    }
}
