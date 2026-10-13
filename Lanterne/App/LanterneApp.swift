import SwiftUI
import VialetKit

@main
struct LanterneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared

    /// Teintes de l'app avant le premier rendu (et police Bricolage Grotesque des titres).
    init() { Theme.configure(Brand.palette) }

    var body: some Scene {
        Window("Habitudes", id: "main") {
            MainWindow()
                .environment(state)
                .fontDesign(.rounded)
                .frame(minWidth: 720, minHeight: 460)
                .onAppear { AppearanceChoice.current(defaultsKey: Brand.key("Appearance")).apply(defaultsKey: Brand.key("Appearance")) }
                .captureOpenWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 920, height: 600)
        .commands {
            AboutCommands(identity: Brand.identity)
            UpdateCommands(updater: .shared)
            CommandGroup(replacing: .newItem) {
                Button("Chercher\u{2026}") { AppState.shared.showPanel() }
                    .keyboardShortcut("f")
            }
        }

        Settings {
            SettingsView().environment(state)
        }

        MenuBarExtra(isInserted: MenuBarPresence.shared.binding) {
            MenuBarContent().environment(state)
        } label: {
            MenuBarIcon(glyph: Brand.glyph)
        }
    }
}
