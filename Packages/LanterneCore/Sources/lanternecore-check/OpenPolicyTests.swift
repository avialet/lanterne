import Foundation
import LanterneCore

private func reveals(_ path: String, executable: Bool = false) -> Bool {
    OpenPolicy.revealsInsteadOfOpening(path: path, isExecutableFile: executable)
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
        for path in ["/tmp/Rapport.pdf", "/tmp/notes.md", "/tmp/photo.jpg", "/tmp/Budget.numbers", "/Applications/Notes.app",
                     "/tmp/dossier"] {
            expect(!reveals(path), path)
        }
        expect(!reveals("/Applications/Outil.app", executable: true), "une app reste ouvrable")
    },
])
