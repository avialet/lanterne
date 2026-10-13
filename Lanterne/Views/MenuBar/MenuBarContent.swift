import SwiftUI
import LanterneCore

struct MenuBarContent: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Button("Chercher\u{2026} (\(HotKeyController.shared.shortcut.display))") { state.showPanel() }
        Button("Ce que Lanterne a appris") { WindowSummoner.show() }
        Divider()
        Toggle("Apprentissage en pause", isOn: $state.learningPaused)
        Divider()
        Button("\u{00C0} propos de \(Brand.displayName)") { AboutPanel.show(Brand.identity) }
        SettingsLink { Text("R\u{00E9}glages\u{2026}") }
        Button("Quitter") { NSApp.terminate(nil) }
    }
}
