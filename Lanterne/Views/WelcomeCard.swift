import SwiftUI
import LanterneCore

/// Carte d'accueil de la fenetre Habitudes : tant qu'un raccourci systeme passe avant celui de Lanterne.
struct WelcomeCard: View {
    @Environment(AppState.self) private var state
    let conflict: SymbolicHotKey

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(HotKeyController.shared.shortcut.display) est d\u{00E9}j\u{00E0} pris par macOS")
                    .font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("Le raccourci \u{00AB}\u{00A0}\(conflict.title)\u{00A0}\u{00BB} passe avant Lanterne. D\u{00E9}cochez-le dans R\u{00E9}glages Syst\u{00E8}me \u{203A} Clavier \u{203A} Raccourcis clavier\u{2026}, ou choisissez un autre raccourci.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                PillButton("Ouvrir Clavier", primary: true) { ShortcutConflicts.openKeyboardSettings() }
                SettingsLink { Pill("Changer\u{2026}") }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Carte d'accueil : Documents, Bureau et Telechargements caches par macOS tant que l'acces n'est pas donne.
struct FolderAccessCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let denied = state.folderAccess == .denied
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Documents, Bureau et T\u{00E9}l\u{00E9}chargements")
                    .font(Theme.ui(13, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(denied
                     ? "Acc\u{00E8}s refus\u{00E9} pour au moins un dossier. \u{00C0} rouvrir dans R\u{00E9}glages Syst\u{00E8}me \u{203A} Confidentialit\u{00E9} et s\u{00E9}curit\u{00E9} \u{203A} Fichiers et dossiers."
                     : "macOS cache ces dossiers \u{00E0} Lanterne\u{00A0}: leurs fichiers r\u{00E9}cents n'apparaissent pas. Autorisez l'acc\u{00E8}s pour les retrouver\u{00A0}; Lanterne ne lit que leurs noms, par Spotlight, et rien ne quitte ce Mac.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                if denied {
                    PillButton("Ouvrir les R\u{00E9}glages", primary: true) { FolderAccess.openSettings() }
                } else {
                    PillButton("Autoriser", primary: true) { state.requestFolderAccess() }
                }
                PillButton("Plus tard") { state.folderAccess = .dismissed }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}
