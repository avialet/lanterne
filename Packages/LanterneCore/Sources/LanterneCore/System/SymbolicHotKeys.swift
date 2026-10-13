import Foundation

/// Raccourci systeme (domaine `com.apple.symbolichotkeys`, cle `AppleSymbolicHotKeys`) : le systeme passe
/// avant un raccourci Carbon, sans que l'enregistrement echoue. On lit donc ces preferences pour prevenir.
public struct SymbolicHotKey: Equatable, Sendable {
    public let id: Int
    public let enabled: Bool
    public let keyCode: Int
    /// Modificateurs au format `NSEvent.ModifierFlags` (comme `HotKeyShortcut.modifiers`).
    public let modifiers: UInt

    public var title: String { SymbolicHotKeys.titles[id] ?? "Raccourci syst\u{00E8}me \(id)" }
}

public enum SymbolicHotKeys {
    static let modifierMask: UInt = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
    static let space = 49

    public static let spotlight = 64

    static let titles: [Int: String] = [
        60: "S\u{00E9}lectionner la source de saisie pr\u{00E9}c\u{00E9}dente",
        61: "S\u{00E9}lectionner la source suivante dans le menu Saisie",
        64: "Afficher la recherche Spotlight",
        65: "Afficher la fen\u{00EA}tre de recherche du Finder",
    ]

    /// Valeurs d'usine de macOS pour les raccourcis sur Espace (absents des preferences tant qu'on ne les
    /// a pas modifies) : Ctrl-Espace, Ctrl-Opt-Espace, Cmd-Espace, Opt-Cmd-Espace, tous actifs.
    static let factory: [SymbolicHotKey] = [
        SymbolicHotKey(id: 60, enabled: true, keyCode: space, modifiers: 1 << 18),
        SymbolicHotKey(id: 61, enabled: true, keyCode: space, modifiers: (1 << 18) | (1 << 19)),
        SymbolicHotKey(id: 64, enabled: true, keyCode: space, modifiers: 1 << 20),
        SymbolicHotKey(id: 65, enabled: true, keyCode: space, modifiers: (1 << 20) | (1 << 19)),
    ]

    /// Table des raccourcis suivis, preferences lues par-dessus les valeurs d'usine. Entrees inconnues ignorees.
    public static func parse(_ preferences: [String: Any]?) -> [Int: SymbolicHotKey] {
        var table: [Int: SymbolicHotKey] = [:]
        for key in factory { table[key.id] = key }
        for (raw, value) in preferences ?? [:] {
            guard let id = Int(raw), let base = table[id], let entry = value as? [String: Any] else { continue }
            let enabled = SettingsCatalog.flag(entry["enabled"])
            var keyCode = base.keyCode, modifiers = base.modifiers
            if let v = entry["value"] as? [String: Any], let p = v["parameters"] as? [Any], p.count >= 3,
               let code = (p[1] as? NSNumber)?.intValue, let mods = (p[2] as? NSNumber)?.uintValue {
                keyCode = code
                modifiers = mods & modifierMask
            }
            table[id] = SymbolicHotKey(id: id, enabled: enabled, keyCode: keyCode, modifiers: modifiers)
        }
        return table
    }

    /// Raccourci systeme actif identique a celui-ci, s'il y en a un.
    public static func conflict(keyCode: Int, modifiers: UInt, in table: [Int: SymbolicHotKey]) -> SymbolicHotKey? {
        let mods = modifiers & modifierMask
        return table.values.sorted { $0.id < $1.id }
            .first { $0.enabled && $0.keyCode == keyCode && $0.modifiers == mods }
    }

    /// Cmd-Espace est-il encore pris par Spotlight ?
    public static func isSpotlightEnabled(_ table: [Int: SymbolicHotKey]) -> Bool {
        table[spotlight]?.enabled ?? true
    }
}
