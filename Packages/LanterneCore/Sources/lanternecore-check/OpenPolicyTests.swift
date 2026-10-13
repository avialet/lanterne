import Foundation
import LanterneCore

private func reveals(_ path: String, executable: Bool = false, directory: Bool = false) -> Bool {
    OpenPolicy.revealsInsteadOfOpening(path: path, isExecutableFile: executable, isDirectory: directory)
}

let openPolicyTests: (String, [Test]) = ("OpenPolicy", [
    Test("scriptsAndInstallersAreShownNotOpened") {
        for path in ["/tmp/a.command", "/tmp/a.sh", "/tmp/a.zsh", "/tmp/a.py", "/tmp/a.rb", "/tmp/a.pl", "/tmp/a.terminal",
                     "/tmp/a.tool", "/tmp/a.workflow", "/tmp/a.scpt", "/tmp/a.scptd", "/tmp/a.action", "/tmp/a.jar",
                     "/tmp/a.pkg", "/tmp/a.mpkg", "/tmp/a.webloc", "/tmp/a.inetloc", "/tmp/a.fileloc", "/tmp/A.COMMAND"] {
            expect(reveals(path), path)
        }
    },
    Test("executableFileWithoutExtension") {
        expect(reveals("/tmp/outil", executable: true))
        expect(!reveals("/tmp/notes"), "fichier ordinaire")
    },
    Test("documentsAndAppsStillOpen") {
        for path in ["/tmp/Rapport.pdf", "/tmp/notes.md", "/tmp/photo.jpg", "/tmp/Budget.numbers", "/tmp/dossier"] {
            expect(!reveals(path), path)
        }
        expect(!reveals("/Applications/Notes.app", directory: true), "une vraie app (paquet) reste ouvrable")
    },
    Test("fakeAppFileIsShown") {
        // Un fichier ou un lien nomme x.app qui n'est pas un paquet d'app : montre, jamais ouvert.
        expect(reveals("/tmp/x.app"), "fichier x.app")
        expect(reveals("/tmp/x.app", executable: true), "script nomme x.app")
        expect(reveals("/tmp/X.APP"), "majuscules")
    },
])
