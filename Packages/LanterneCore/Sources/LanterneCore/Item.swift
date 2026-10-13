import Foundation

/// Genre d'element que Lanterne trouve et ouvre.
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case app, setting, file, folder, action

    /// Libelle de section des resultats.
    public var sectionTitle: String {
        switch self {
        case .app: "Apps"
        case .setting: "R\u{00E9}glages"
        case .file, .folder: "Fichiers et dossiers"
        case .action: "Actions"
        }
    }
}

/// Element trouvable : app, panneau des Reglages Systeme, fichier ou dossier, action d'une app vialet.
/// La cle est stable d'une session a l'autre (`app:<bundle id>`, `file:<chemin>`, `setting:<id>`,
/// `action:<bundle>#<id>`) : c'est elle que retiennent les habitudes.
public struct Item: Sendable, Hashable, Identifiable {
    public let key: String
    public let title: String
    /// Chemin abrege, nom de l'app d'une action, "Reglages Systeme"...
    public let subtitle: String
    /// Autres noms (nom anglais d'une app, termes de recherche d'un reglage).
    public let keywords: [String]
    public let kind: ItemKind
    /// Chemin (app, fichier, dossier) ou URL (reglage, action).
    public let target: String
    /// A priori Spotlight pour le demarrage a froid : derniere ouverture et nombre d'ouvertures.
    public let lastUsed: Date?
    public let useCount: Int

    public var id: String { key }

    public init(key: String, title: String, subtitle: String = "", keywords: [String] = [], kind: ItemKind,
                target: String, lastUsed: Date? = nil, useCount: Int = 0) {
        self.key = key
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.kind = kind
        self.target = target
        self.lastUsed = lastUsed
        self.useCount = useCount
    }

    public static func appKey(_ bundleIdentifier: String) -> String { "app:" + bundleIdentifier }
    public static func fileKey(_ path: String) -> String { "file:" + path }
    public static func settingKey(_ identifier: String) -> String { "setting:" + identifier }
    public static func actionKey(bundle: String, id: String) -> String { "action:\(bundle)#\(id)" }

    /// Chemin d'une cle `file:` ; nil pour les autres.
    public static func path(fromKey key: String) -> String? {
        key.hasPrefix("file:") ? String(key.dropFirst(5)) : nil
    }
}
