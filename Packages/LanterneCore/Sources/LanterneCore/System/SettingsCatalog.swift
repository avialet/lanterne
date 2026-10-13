import Foundation

/// Panneaux des Reglages Systeme, lus dans les extensions `com.apple.Settings.extension.ui`
/// (`/System/Library/ExtensionKit/Extensions/*.appex`) : nom francais dans `InfoPlist.loctable`, termes de
/// recherche dans `fr.lproj/<nom>.searchTerms`. Format non documente : lecture tolerante, liste figee en repli.
/// Le coeur recoit des dictionnaires deja decodes ; l'app lit les fichiers.
public enum SettingsCatalog {
    public static let extensionPoint = "com.apple.Settings.extension.ui"
    public static let urlScheme = "x-apple.systempreferences:"
    public static let subtitle = "R\u{00E9}glages Syst\u{00E8}me"
    static let maxKeywords = 120

    /// L'element d'un panneau, ou nil si l'extension n'en est pas un, ne s'ouvre pas par URL ou n'a pas de
    /// nom lisible. `localizedNames` : contenu de `InfoPlist.loctable` (langue -> cles) ; `searchTerms` :
    /// contenu de `<langue>.lproj/<searchTermsFileName>.searchTerms`.
    public static func item(info: [String: Any], localizedNames: [String: Any]?, searchTerms: [String: Any]?,
                            languages: [String] = ["fr", "fr_CA"]) -> Item? {
        guard let id = info["CFBundleIdentifier"] as? String, !id.isEmpty,
              let ex = info["EXAppExtensionAttributes"] as? [String: Any],
              ex["EXExtensionPointIdentifier"] as? String == extensionPoint,
              let attributes = ex["SettingsExtensionAttributes"] as? [String: Any],
              flag(attributes["allowsXAppleSystemPreferencesURLScheme"]) else { return nil }
        var name: String?
        for language in languages {
            if let table = localizedNames?[language] as? [String: Any], let n = table["CFBundleDisplayName"] as? String {
                name = n.trimmingCharacters(in: .whitespaces)
                break
            }
        }
        if name == nil || isTechnicalName(name!) || name!.isEmpty { name = fallbackNames[id] }
        guard let title = name else { return nil }
        var keywords: [String] = []
        var seen = Set<String>([title])
        func add(_ word: String) {
            let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !w.isEmpty, w.count <= 80, keywords.count < maxKeywords, seen.insert(w).inserted else { return }
            keywords.append(w)
        }
        if let english = info["CFBundleDisplayName"] as? String, !isTechnicalName(english) { add(english) }
        if let searchTerms { searchTermsKeywords(searchTerms).forEach(add) }
        return Item(key: Item.settingKey(id), title: title, subtitle: subtitle, keywords: keywords, kind: .setting,
                    target: urlScheme + id)
    }

    /// Titres des sections et termes d'indexation ("dicter, dictee, micro"), dans l'ordre des sections.
    public static func searchTermsKeywords(_ plist: [String: Any]) -> [String] {
        var out: [String] = []
        for key in plist.keys.sorted() {
            guard let section = plist[key] as? [String: Any],
                  let strings = section["localizableStrings"] as? [[String: Any]] else { continue }
            for entry in strings {
                if let title = entry["title"] as? String { out.append(title) }
                if let index = entry["index"] as? String {
                    out += index.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                }
            }
        }
        return out
    }

    /// Nom interne laisse sans traduction ("PowerPreferences", "FollowUps") : un seul mot, suffixe
    /// technique ou majuscule au milieu (au-dela de la deuxieme lettre, pour garder "iCloud").
    public static func isTechnicalName(_ name: String) -> Bool {
        guard !name.contains(where: \.isWhitespace) else { return false }
        if ["Extension", "Settings", "Preferences", "Plugin"].contains(where: { name.hasSuffix($0) }) { return true }
        let chars = Array(name)
        guard chars.count > 3 else { return false }
        for i in 2..<chars.count where chars[i].isUppercase && chars[i - 1].isLowercase { return true }
        return false
    }

    /// Catalogue lu, ou la liste figee s'il est trop maigre (format change, dossier illisible).
    public static func catalog(found: [Item]) -> [Item] {
        found.count >= 10 ? found : fallback
    }

    static func flag(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return false
    }

    /// Noms francais des panneaux dont l'extension n'en donne pas.
    static let fallbackNames: [String: String] = [
        "com.apple.Battery-Settings.extension": "Batterie",
    ]

    /// Liste figee (macOS 26) : identifiant d'extension, nom francais, quelques mots-cles.
    static let frozen: [(String, String, [String])] = [
        ("com.apple.wifi-settings-extension", "Wi\u{2011}Fi", ["wifi", "sans fil", "r\u{00E9}seau"]),
        ("com.apple.BluetoothSettings", "Bluetooth", ["casque", "souris", "clavier"]),
        ("com.apple.Network-Settings.extension", "R\u{00E9}seau", ["ethernet", "proxy", "dns"]),
        ("com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension", "VPN", ["tunnel"]),
        ("com.apple.Notifications-Settings.extension", "Notifications", ["alertes", "banni\u{00E8}res"]),
        ("com.apple.Sound-Settings.extension", "Son", ["volume", "micro", "haut-parleur"]),
        ("com.apple.Focus-Settings.extension", "Concentration", ["ne pas d\u{00E9}ranger"]),
        ("com.apple.Screen-Time-Settings.extension", "Temps d\u{2019}\u{00E9}cran", ["limites"]),
        ("com.apple.Appearance-Settings.extension", "Apparence", ["sombre", "clair", "accent"]),
        ("com.apple.Accessibility-Settings.extension", "Accessibilit\u{00E9}", ["voiceover", "zoom", "contraste"]),
        ("com.apple.ControlCenter-Settings.extension", "Barre des menus", ["centre de contr\u{00F4}le"]),
        ("com.apple.Siri-Settings.extension", "Siri", ["assistant"]),
        ("com.apple.Spotlight-Settings.extension", "Spotlight", ["recherche"]),
        ("com.apple.settings.PrivacySecurity.extension", "Confidentialit\u{00E9} et s\u{00E9}curit\u{00E9}", ["autorisations", "accessibilit\u{00E9}"]),
        ("com.apple.Desktop-Settings.extension", "Bureau et Dock", ["dock", "mission control", "coins actifs"]),
        ("com.apple.Displays-Settings.extension", "Moniteurs", ["\u{00E9}cran", "r\u{00E9}solution", "luminosit\u{00E9}"]),
        ("com.apple.Wallpaper-Settings.extension", "Fond d\u{2019}\u{00E9}cran", ["image"]),
        ("com.apple.Lock-Screen-Settings.extension", "\u{00C9}cran verrouill\u{00E9}", ["veille", "mot de passe"]),
        ("com.apple.Touch-ID-Settings.extension", "Touch ID et mot de passe", ["empreinte"]),
        ("com.apple.Users-Groups-Settings.extension", "Utilisateurs et groupes", ["compte", "invit\u{00E9}"]),
        ("com.apple.Internet-Accounts-Settings.extension", "Comptes Internet", ["mail", "agenda"]),
        ("com.apple.Keyboard-Settings.extension", "Clavier", ["raccourcis", "dict\u{00E9}e", "saisie"]),
        ("com.apple.Mouse-Settings.extension", "Souris", ["d\u{00E9}filement"]),
        ("com.apple.Trackpad-Settings.extension", "Trackpad", ["gestes", "clic"]),
        ("com.apple.Print-Scan-Settings.extension", "Imprimantes et scanners", ["imprimer"]),
        ("com.apple.Battery-Settings.extension", "Batterie", ["\u{00E9}nergie", "charge"]),
        ("com.apple.Date-Time-Settings.extension", "Date et heure", ["fuseau horaire", "horloge"]),
        ("com.apple.Sharing-Settings.extension", "Partage", ["partage d\u{2019}\u{00E9}cran", "fichiers"]),
        ("com.apple.Time-Machine-Settings.extension", "Time Machine", ["sauvegarde"]),
        ("com.apple.Software-Update-Settings.extension", "Mise \u{00E0} jour de logiciels", ["macos", "mise \u{00E0} jour"]),
        ("com.apple.settings.Storage", "Stockage", ["disque", "espace"]),
        ("com.apple.LoginItems-Settings.extension", "Ouverture", ["\u{00E9}l\u{00E9}ments de connexion", "d\u{00E9}marrage"]),
        ("com.apple.Localization-Settings.extension", "Langue et r\u{00E9}gion", ["langue", "format"]),
        ("com.apple.SystemProfiler.AboutExtension", "Informations", ["\u{00E0} propos", "num\u{00E9}ro de s\u{00E9}rie"]),
    ]

    public static var fallback: [Item] {
        frozen.map { id, name, keywords in
            Item(key: Item.settingKey(id), title: name, subtitle: subtitle, keywords: keywords, kind: .setting,
                 target: urlScheme + id)
        }
    }
}
