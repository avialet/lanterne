import AppKit
import LanterneCore
import VialetKit

/// Raccourcis systeme qui passent avant celui de Lanterne (preferences `com.apple.symbolichotkeys`).
enum ShortcutConflicts {
    static func table() -> [Int: SymbolicHotKey] {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
        return SymbolicHotKeys.parse(value)
    }

    static func conflict(for shortcut: HotKeyShortcut, in table: [Int: SymbolicHotKey] = table()) -> SymbolicHotKey? {
        SymbolicHotKeys.conflict(keyCode: Int(shortcut.keyCode), modifiers: shortcut.modifiers, in: table)
    }

    /// Reglages Systeme › Clavier (les raccourcis sont sous « Raccourcis clavier… »).
    static func openKeyboardSettings() {
        if let url = URL(string: SettingsCatalog.urlScheme + "com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static let commandSpace = HotKeyShortcut.space([.command])
}
