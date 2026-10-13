import AppKit
import UniformTypeIdentifiers
import LanterneCore

/// Ouvre, montre dans le Finder, copie le chemin ; icones des elements (sans lire les fichiers).
@MainActor
enum Launcher {
    @discardableResult
    static func open(_ item: Item) -> Bool {
        switch item.kind {
        case .app:
            let url = URL(fileURLWithPath: item.target)
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return true
        case .file, .folder:
            let url = URL(fileURLWithPath: item.target)
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            return NSWorkspace.shared.open(url)
        case .setting, .action:
            guard let url = URL(string: item.target) else { return false }
            return NSWorkspace.shared.open(url)
        }
    }

    /// Montre l'element dans le Finder (app, fichier, dossier) ; false pour un reglage ou une action.
    @discardableResult
    static func reveal(_ item: Item) -> Bool {
        guard [.app, .file, .folder].contains(item.kind) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.target)])
        return true
    }

    static func copyPath(_ item: Item) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.target, forType: .string)
    }
}

/// Icones : vraies icones des apps et des panneaux, icone du type pour les fichiers (aucune lecture de fichier).
@MainActor
enum Icons {
    private static var cache: [String: NSImage] = [:]
    /// Chemin a utiliser pour l'icone d'un reglage (extension) ou d'une action (app).
    static var paths: [String: String] = [:]

    static func image(for item: Item) -> NSImage {
        if let cached = cache[item.key] { return cached }
        let image: NSImage
        switch item.kind {
        case .app:
            image = NSWorkspace.shared.icon(forFile: item.target)
        case .setting:
            image = NSWorkspace.shared.icon(forFile: paths[item.key] ?? "/System/Applications/System Settings.app")
        case .action:
            image = NSWorkspace.shared.icon(forFile: paths[item.key] ?? "/System/Applications/Utilities")
        case .folder:
            image = NSWorkspace.shared.icon(for: .folder)
        case .file:
            let ext = (item.target as NSString).pathExtension
            image = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        }
        cache[item.key] = image
        return image
    }
}
