#if DEBUG
import AppKit
import SwiftUI
import LanterneCore

/// Mode capture sans ecran (voir SnapshotRunner) : `Lanterne -LanterneSnapshot <dossier>
/// [-LanterneSnapshotSeed 1] [-LanterneSnapshotAppearance dark] [-LanterneSnapshotOnly a,b]`, avec
/// LANTERNE_DB_PATH vers une base jetable. Apps du systeme seulement, fichiers d'exemple (chemins fictifs),
/// 40 ouvertures fictives sur 3 semaines, contexte impose (9 h, depuis Mail). Scenarios : standard
/// (`mainWindow` = Habitudes, `settings`, `about`, `update`), `floatingPanel` (champ vide), `query` ("cla"
/// tape, avec "Plus loin"), `conflit` (cartes d'accueil du raccourci et de l'acces aux dossiers), `vide` (Habitudes sans rien d'appris).
extension AppDelegate {
    func runSnapshotIfRequested() -> Bool {
        guard SnapshotRequest.parse(prefix: Brand.name, arguments: CommandLine.arguments) != nil else { return false }
        let state = AppState.shared
        state.demo = true
        let seeded = UserDefaults.standard.bool(forKey: Brand.key("SnapshotSeed"))
        if seeded { Self.seed(state) }
        state.setDemoFiles(Self.demoFiles)
        state.reloadSources()
        let context = SearchContext(now: Date(), hour: 9, contextApp: "com.apple.mail")

        func ready() async {
            for _ in 0..<80 {
                if state.index.item(forKey: Item.appKey("com.apple.mail")) != nil,
                   state.index.item(forKey: Self.demoFiles[0].key) != nil,
                   state.index.item(forKey: Item.settingKey("com.apple.Keyboard-Settings.extension")) != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        func panelWindow() -> NSWindow? { NSApp.windows.first { $0 is FloatingPanel && $0.isVisible } }

        let main = SnapshotScenario("mainWindow") {
            await ready()
            state.debugSetConflict(nil)
            try await Task.sleep(for: .seconds(1.5))
            return WindowSummoner.mainWindow
        }
        let conflict = SnapshotScenario("conflit") {
            await ready()
            state.debugSetConflict(SymbolicHotKeys.parse(nil)[60])
            state.debugShowFolderAccessCard(true)
            try await Task.sleep(for: .seconds(1))
            return WindowSummoner.mainWindow
        }
        let empty = SnapshotScenario("vide") {
            await ready()
            state.debugSetConflict(nil)
            state.debugShowFolderAccessCard(false)
            state.eraseAll()
            try await Task.sleep(for: .seconds(1))
            return WindowSummoner.mainWindow
        }
        let panel = SnapshotScenario("floatingPanel") {
            await ready()
            state.showPanel(context: context)
            state.query = ""
            state.search()
            if let second = state.rows.dropFirst().first { state.hoveredKey = second.id }
            try await Task.sleep(for: .seconds(1))
            return panelWindow()
        }
        let query = SnapshotScenario("query") {
            await ready()
            if panelWindow() == nil { state.showPanel(context: context) }
            state.hoveredKey = nil
            state.query = "cla"
            state.setFurther(Self.demoFurther)
            try await Task.sleep(for: .seconds(1))
            return panelWindow()
        }
        // Cartes propres a Lanterne (sous les cartes standard des Reglages, hors champ de `settings`).
        let cards = SnapshotScenario("reglagesLanterne") {
            await ready()
            let content = VStack(alignment: .leading, spacing: 18) {
                SpotlightCard()
                SourcesCard()
                LearningCard()
                ExclusionsCard()
            }
            .toggleStyle(.switch)
            .font(Theme.ui(13))
            .padding(26)
            .frame(width: 500)
            .background(Theme.paper)
            .fontDesign(.rounded)
            .tint(Theme.accent)
            .environment(state)
            let hosting = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(800))
            return window
        }
        let standard = SnapshotRunner.standardScenarios(mainWindow: { WindowSummoner.mainWindow }, identity: Brand.identity)
            .filter { $0.name != "floatingPanel" }
        // `vide` efface la base jetable : en dernier.
        return SnapshotRunner.runIfRequested(prefix: Brand.name, scenarios: [main] + standard + [cards, panel, query, conflict, empty])
    }

    /// Fichiers d'exemple : chemins fictifs, aucun fichier lu.
    static let demoFiles: [Item] = {
        let folder = "/Users/Shared/Exemples"
        let now = Date()
        let names: [(String, Double)] = [
            ("Rapport annuel 2026.pdf", 1), ("Budget 2026.numbers", 2), ("Notes de r\u{00E9}union.md", 3),
            ("Classement des factures.numbers", 6), ("Planning de l\u{2019}\u{00E9}quipe.xlsx", 4),
            ("Plan du jardin.png", 12), ("Contrat de location.pdf", 20),
        ]
        return names.map { name, days in
            Item(key: Item.fileKey(folder + "/" + name), title: name, subtitle: folder, kind: .file,
                 target: folder + "/" + name, lastUsed: now.addingTimeInterval(-days * 86400))
        } + [Item(key: Item.fileKey(folder + "/Classeurs"), title: "Classeurs", subtitle: folder, kind: .folder,
                  target: folder + "/Classeurs", lastUsed: now.addingTimeInterval(-9 * 86400))]
    }()

    static let demoFurther: [Item] = ["D\u{00E9}claration 2026.pdf", "\u{00C9}clairage du salon.jpg", "Recettes classiques.pages"].map {
        let path = "/Users/Shared/Archives/" + $0
        return Item(key: Item.fileKey(path), title: $0, subtitle: "/Users/Shared/Archives", kind: .file, target: path)
    }

    /// 40 ouvertures fictives reparties sur 3 semaines (apps et reglages du systeme, fichiers d'exemple).
    static func seed(_ state: AppState) {
        let now = Date()
        let calendar = Calendar.current
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 10) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let plan: [(key: String, title: String, kind: ItemKind, times: [(Int, Int)], context: String?, prefix: String)] = [
            (Item.appKey("com.apple.mail"), "Mail", .app, [(0, 8), (1, 8), (2, 9), (3, 8), (4, 9), (6, 8), (7, 8), (8, 9), (10, 8), (13, 9), (15, 8), (20, 9)], "com.apple.iCal", ""),
            (Item.appKey("com.apple.iCal"), "Calendrier", .app, [(1, 9), (2, 9), (5, 9), (8, 9), (9, 10), (14, 9), (19, 9)], "com.apple.mail", "cal"),
            (Item.appKey("com.apple.Notes"), "Notes", .app, [(0, 10), (2, 11), (4, 10), (7, 11), (11, 10), (16, 10)], "com.apple.mail", "no"),
            (Item.appKey("com.apple.Safari"), "Safari", .app, [(1, 14), (3, 15), (6, 13), (12, 16), (17, 14)], nil, "sa"),
            (Item.settingKey("com.apple.Keyboard-Settings.extension"), "Clavier", .setting, [(2, 9), (9, 9), (18, 10)], "com.apple.mail", "cla"),
            (Item.fileKey("/Users/Shared/Exemples/Rapport annuel 2026.pdf"), "Rapport annuel 2026.pdf", .file, [(1, 9), (3, 9), (8, 10), (12, 9)], "com.apple.mail", "rap"),
            (Item.appKey("com.apple.Music"), "Musique", .app, [(2, 21), (5, 21), (11, 22)], nil, "mu"),
        ]
        for entry in plan {
            for (days, hour) in entry.times {
                let date = at(days, hour)
                let weekday = calendar.component(.weekday, from: date)
                _ = try? state.store.record(Opening(itemKey: entry.key, title: entry.title, kind: entry.kind, openedAt: date,
                                                    hour: hour, weekday: weekday, contextApp: entry.context, prefix: entry.prefix))
            }
        }
        state.reloadHabits()
    }
}
#endif
