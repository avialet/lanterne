import Foundation
import LanterneCore

/// Panneaux des Reglages Systeme, lus dans `/System/Library/ExtensionKit/Extensions` (voir SettingsCatalog).
enum SettingsIndex {
    static let directory = "/System/Library/ExtensionKit/Extensions"

    /// Elements et chemin de l'extension de chacun (pour son icone). Hors fil principal.
    static func load() -> (items: [Item], extensionPaths: [String: String]) {
        let fm = FileManager.default
        var items: [Item] = []
        var paths: [String: String] = [:]
        for name in ((try? fm.contentsOfDirectory(atPath: directory)) ?? []).sorted() where name.hasSuffix(".appex") {
            let contents = URL(fileURLWithPath: directory).appendingPathComponent(name).appendingPathComponent("Contents")
            guard let info = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")) as? [String: Any],
                  let ex = info["EXAppExtensionAttributes"] as? [String: Any],
                  ex["EXExtensionPointIdentifier"] as? String == SettingsCatalog.extensionPoint else { continue }
            let resources = contents.appendingPathComponent("Resources")
            let names = plist(resources.appendingPathComponent("InfoPlist.loctable"))
            var terms: [String: Any]?
            if let attributes = ex["SettingsExtensionAttributes"] as? [String: Any],
               let file = attributes["searchTermsFileName"] as? String, !file.isEmpty, !file.contains("/") {
                terms = plist(resources.appendingPathComponent("fr.lproj").appendingPathComponent(file + ".searchTerms"))
            }
            guard let item = SettingsCatalog.item(info: info, localizedNames: names, searchTerms: terms) else { continue }
            items.append(item)
            paths[item.key] = contents.deletingLastPathComponent().path
        }
        let catalog = SettingsCatalog.catalog(found: items)
        return (catalog, catalog.count == items.count ? paths : [:])
    }

    private static func plist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
