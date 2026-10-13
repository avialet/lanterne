import AppKit
import CoreServices
import LanterneCore

/// Apps installees : `/Applications` (et ses sous-dossiers), `/System/Applications`, `~/Applications`,
/// `/System/Library/CoreServices/Applications` et le Finder. Nom localise (« Calculette ») et nom anglais en
/// mot-cle (« Calculator ») ; dedoublonnage par bundle id ; a priori Spotlight (derniere ouverture, nombre).
enum AppIndex {
    /// Dossier et profondeur de parcours (2 : un niveau de sous-dossiers, comme Utilitaires).
    static func roots(systemOnly: Bool = false) -> [(path: String, depth: Int)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let system: [(String, Int)] = [("/System/Applications", 2), ("/System/Library/CoreServices/Applications", 1)]
        return systemOnly ? system : [("/Applications", 2)] + system + [(home + "/Applications", 2)]
    }

    static let extras = ["/System/Library/CoreServices/Finder.app"]

    /// Dates de modification des dossiers parcourus : un changement declenche un nouveau parcours.
    static func signature(systemOnly: Bool = false) -> [String: Date] {
        var out: [String: Date] = [:]
        let fm = FileManager.default
        for (root, depth) in roots(systemOnly: systemOnly) {
            out[root] = (try? fm.attributesOfItem(atPath: root)[.modificationDate]) as? Date
            guard depth > 1, let children = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for child in children where !child.hasSuffix(".app") && !child.hasPrefix(".") {
                let path = root + "/" + child
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    out[path] = (try? fm.attributesOfItem(atPath: path)[.modificationDate]) as? Date
                }
            }
        }
        return out
    }

    /// Parcours complet (hors fil principal).
    static func scan(systemOnly: Bool = false) -> [Item] {
        var bundles: [String] = []
        let fm = FileManager.default
        func walk(_ dir: String, depth: Int) {
            guard let children = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for child in children.sorted() where !child.hasPrefix(".") {
                let path = dir + "/" + child
                if child.hasSuffix(".app") {
                    bundles.append(path)
                } else if depth > 1 {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { walk(path, depth: depth - 1) }
                }
            }
        }
        for (root, depth) in roots(systemOnly: systemOnly) { walk(root, depth: depth) }
        if !systemOnly { bundles += extras.filter { fm.fileExists(atPath: $0) } }
        var seen = Set<String>()
        var items: [Item] = []
        for path in bundles {
            guard let item = item(at: path), seen.insert(item.key).inserted else { continue }
            items.append(item)
        }
        return items
    }

    static func item(at path: String) -> Item? {
        let url = URL(fileURLWithPath: path)
        let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        if info["LSUIElement"] as? Bool == true || (info["LSUIElement"] as? String) == "1" { return nil }
        if info["LSBackgroundOnly"] as? Bool == true { return nil }
        let bundleId = info["CFBundleIdentifier"] as? String
        var title = FileManager.default.displayName(atPath: path)
        if title.hasSuffix(".app") { title = String(title.dropLast(4)) }
        let fileName = String(url.lastPathComponent.dropLast(4))
        var keywords: [String] = []
        for candidate in [fileName, info["CFBundleName"] as? String, info["CFBundleDisplayName"] as? String] {
            if let c = candidate, !c.isEmpty, c != title, !keywords.contains(c) { keywords.append(c) }
        }
        let parent = FileManager.default.displayName(atPath: url.deletingLastPathComponent().path)
        let usage = SpotlightAttributes.usage(of: url)
        return Item(key: Item.appKey(bundleId ?? path), title: title, subtitle: parent, keywords: keywords, kind: .app,
                    target: path, lastUsed: usage.lastUsed, useCount: usage.useCount)
    }
}

/// Attributs Spotlight d'un fichier : derniere ouverture et nombre d'ouvertures (`kMDItemUseCount`, hors
/// en-tetes publics : lu par cle texte, en bonus).
enum SpotlightAttributes {
    static func usage(of url: URL) -> (lastUsed: Date?, useCount: Int) {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return (nil, 0) }
        let last = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        let count = (MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? NSNumber)?.intValue ?? 0
        return (last, count)
    }
}
