import Foundation

/// URL d'une action annoncee par une autre app vialet.app dans sa fiche (non fiable) : seulement le schema de
/// l'app elle-meme (`fr.vialet.<nom>` -> `<nom>://`), un identifiant `[a-z0-9-]{1,40}` non reserve, et une URL
/// relue dont le schema et l'hote sont ceux attendus.
public enum VialetActionLink {
    public static let bundlePrefix = "fr.vialet."

    public static func url(bundleIdentifier: String, scheme: String, actionId: String) -> URL? {
        guard bundleIdentifier.hasPrefix(bundlePrefix) else { return nil }
        let name = String(bundleIdentifier.dropFirst(bundlePrefix.count))
        guard (1...30).contains(name.count), let first = name.unicodeScalars.first, ("a"..."z").contains(first),
              name.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) }),
              scheme == name,
              AppAction.isValidIdentifier(actionId), !AppURLCommand.reserved.contains(actionId),
              let url = URL(string: "\(name)://\(actionId)"),
              url.scheme == name, url.host(percentEncoded: true) == actionId,
              url.path(percentEncoded: true).isEmpty, url.query == nil, url.fragment == nil else { return nil }
        return url
    }
}
