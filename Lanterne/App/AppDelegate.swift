import AppKit
import VialetKit
import LanterneCore

extension AppActions {
    /// Actions rapides de Lanterne, pour Vialet et les liens `lanterne://`.
    static let shared = AppActions(Brand.identity, open: { WindowSummoner.show() },
                                   checkForUpdates: { WindowSummoner.show(); Updater.shared.check() })
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Mode capture et sondes : ni raccourci global, ni reseau, ni donnees reelles.
        if runSnapshotIfRequested() || runProbeIfRequested() { return }
        #endif
        AppState.shared.start()
        HotKeyController.shared.start { AppState.shared.togglePanel() }
        AppActions.shared.register(AppAction("chercher", title: "Chercher", symbol: "magnifyingglass",
                                             shortcut: HotKeyController.shared.shortcut.display)) {
            AppState.shared.showPanel()
        }
        AppActions.shared.register(AppAction("habitudes", title: "Ce que Lanterne a appris",
                                             symbol: "clock.arrow.circlepath")) {
            WindowSummoner.show()
        }
        _ = DockPresence.shared
        HubPresence.start(menuBar: MenuBarPresence.shared, actions: AppActions.shared, updater: Updater.shared)
        // Laisse l'app s'afficher avant le moindre appel reseau.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            MainActor.assumeIsolated { Updater.shared.checkAutomatically() }
        }
    }

    /// Liens `lanterne://` (`chercher`, `habitudes`, `update`) : voir AppActions.
    func application(_ application: NSApplication, open urls: [URL]) {
        AppActions.shared.handle(urls)
    }

    /// L'app reste disponible (raccourci global, barre des menus) fenetre fermee.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowSummoner.show() }
        return true
    }
}
