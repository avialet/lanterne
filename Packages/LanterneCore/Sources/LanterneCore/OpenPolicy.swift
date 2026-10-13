import Foundation
import UniformTypeIdentifiers

/// Un resultat qui executerait quelque chose (script, executable, installeur, raccourci web ou Automator)
/// ne s'ouvre pas d'un appui sur Retour : il est montre dans le Finder. Une app reste ouvrable.
public enum OpenPolicy {
    /// Extensions toujours montrees plutot qu'ouvertes (en minuscules).
    public static let revealedExtensions: Set<String> = [
        "command", "terminal", "tool", "workflow", "scpt", "scptd", "action", "jar", "pkg", "mpkg",
        "webloc", "inetloc", "fileloc",
    ]

    /// Decision sur le chemin seul (aucune lecture du fichier) : `isExecutableFile` vient de
    /// `FileManager.isExecutableFile` pour un fichier ordinaire (faux pour un dossier) ;
    /// `isDirectory` dit si le chemin est un dossier (une vraie app est un paquet, donc un dossier :
    /// un fichier ou un lien nomme `x.app` qui n'en est pas un est montre, pas ouvert).
    public static func revealsInsteadOfOpening(path: String, isExecutableFile: Bool, isDirectory: Bool = false) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "app" { return !isDirectory }
        if revealedExtensions.contains(ext) { return true }
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .application) { return false }
            if [UTType.unixExecutable, .shellScript, .script, .executable].contains(where: type.conforms(to:)) { return true }
        }
        return isExecutableFile
    }
}
