import AppKit

/// Documents, Bureau et Telechargements : macOS les cache a une app sans autorisation, Spotlight compris
/// (verifie sur l'app empaquetee : 0 resultat dans ces dossiers, contre plusieurs centaines dans le
/// Terminal). L'acces n'est jamais demande d'office : la carte d'accueil l'explique, l'utilisateur choisit.
enum FolderAccess {
    enum State: String {
        /// Pas encore demande.
        case unknown
        case granted
        /// Au moins un dossier refuse : a rouvrir dans les Reglages Systeme.
        case denied
        /// "Plus tard" : la carte ne revient pas.
        case dismissed
    }

    static var folders: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["Documents", "Desktop", "Downloads"].map { home + "/" + $0 }
    }

    /// Lister chaque dossier declenche la demande de macOS (une par dossier) ; vrai si tous sont lisibles.
    /// Bloquant pendant la demande : hors fil principal.
    nonisolated static func request() -> Bool {
        folders.allSatisfy { (try? FileManager.default.contentsOfDirectory(atPath: $0)) != nil }
    }

    /// Un des chemins est-il dans ces dossiers ?
    static func covers(_ path: String) -> Bool {
        folders.contains { path.hasPrefix($0 + "/") }
    }

    /// Reglages Systeme > Confidentialite et securite > Fichiers et dossiers.
    @MainActor static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
}
