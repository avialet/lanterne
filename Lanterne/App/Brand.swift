import SwiftUI
import VialetKit

/// Identite de l'app : le seul fichier Swift qui connait son nom, ses teintes et son glyphe.
enum Brand {
    static let name = "Lanterne"
    static let displayName = "Lanterne"
    /// Teintes de l'affiche (sites, plaques, DMG, interface), calculees par scripts/teintes.py :
    /// texte `deep` sur `background`. Une teinte par ligne `cle: 0x...` (lue par les scripts du socle).
    static let palette = AccentPalette(accent: 0xE0601F, background: 0xE0601F,
                                       deep: 0x3E1301, pale: 0xFEEEE7,
                                       night: 0x2C1308, nightInk: 0xFBCCB8)
    /// Pictogramme de la plaque : sous-ensemble SVG absolu (M L H V C Q Z), boite 0-100, trait non rempli.
    /// Lanterne de papier : anneau, deux bandes, flanc arrondi et flamme.
    static let glyph = "M 50 4 V 14 M 30 14 H 70 M 36 14 C 14 34 14 68 36 88 M 64 14 C 86 34 86 68 64 88 M 30 88 H 70 M 50 36 C 50 46 40 52 40 62 C 40 68 45 72 50 72 C 55 72 60 68 60 62 C 60 52 50 46 50 36 Z"
    /// Trait du glyphe en `deep` plutot qu'en blanc (accent trop clair pour un trait blanc).
    static let strokeDeep = false
    static let identity = AppIdentity(name: name, displayName: displayName, repository: "avialet/lanterne",
                                      bundleIdentifier: "fr.vialet.lanterne", palette: palette, glyph: glyph,
                                      strokeDeep: strokeDeep)
    static let updater = UpdaterConfiguration(identity)

    /// Cles UserDefaults, prefixees par le nom de l'app.
    static func key(_ suffix: String) -> String { identity.key(suffix) }
}

extension Updater {
    static let shared = Updater(configuration: Brand.updater)
}

extension HotKeyController {
    /// Ctrl-Espace par defaut (source de saisie precedente, souvent desactivee : voir ShortcutConflicts) ;
    /// la carte "Remplacer Spotlight" propose Cmd-Espace une fois Spotlight libere.
    static let shared = HotKeyController(defaultsKey: Brand.key("HotKey"), logName: Brand.displayName,
                                         initial: .space([.control]))
}

extension MenuBarPresence {
    /// Icone de barre des menus : masquee quand Vialet rassemble les apps (mode Automatique).
    static let shared = MenuBarPresence(app: Brand.identity)
}

/// Icone du Dock : seulement pendant qu'une fenetre est ouverte (reglage Toujours).
extension DockPresence {
    static let shared = DockPresence(app: Brand.identity)
}

/// Phrase des Reglages sur les echanges reseau : l'app peut tenir le menu rassembleur des apps vialet.app.
extension HubPresence {
    static let updateNote = "\u{00C9}changes r\u{00E9}seau de \(Brand.displayName) : la derni\u{00E8}re version publi\u{00E9}e sur GitHub et, quand son ic\u{00F4}ne rassemble vos apps vialet.app, celle de ces apps et le catalogue de vialet.app une fois par jour. Aucune donn\u{00E9}e n'est envoy\u{00E9}e."
}
