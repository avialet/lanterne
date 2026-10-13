import AppKit
import Observation
import SwiftUI
import LanterneCore

/// Etat partage : sources, index en memoire, habitudes, panneau de recherche et reglages.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    /// Carte du panneau (640 x 440) et marge transparente pour son ombre.
    static let cardSize = CGSize(width: 640, height: 440)
    static let panelMargin: CGFloat = 32
    static var panelSize: CGSize {
        CGSize(width: cardSize.width + 2 * panelMargin, height: cardSize.height + 2 * panelMargin)
    }
    static let memoryChoices = [30, 90, 180, 365]

    let database: AppDatabase
    let store: HabitStore
    @ObservationIgnored private let defaults = UserDefaults.standard

    // MARK: Reglages

    var learningPaused: Bool { didSet { defaults.set(learningPaused, forKey: Brand.key("LearningPaused")) } }
    var memoryDays: Int {
        didSet { defaults.set(memoryDays, forKey: Brand.key("MemoryDays")); purge(); reloadHabits() }
    }
    var useApps: Bool { didSet { saveSource(useApps, "Apps"); reloadSources() } }
    var useSettings: Bool { didSet { saveSource(useSettings, "Settings"); reloadSources() } }
    var useRecents: Bool { didSet { saveSource(useRecents, "Recents"); reloadSources() } }
    var useSpotlight: Bool { didSet { saveSource(useSpotlight, "Spotlight") } }
    var useActions: Bool { didSet { saveSource(useActions, "Actions"); reloadSources() } }
    var excludedFolders: [String] {
        didSet { defaults.set(excludedFolders, forKey: Brand.key("ExcludedFolders")); rebuildIndex() }
    }
    var excludedTypes: String {
        didSet { defaults.set(excludedTypes, forKey: Brand.key("ExcludedTypes")); rebuildIndex() }
    }

    // MARK: Donnees

    private(set) var apps: [Item] = []
    private(set) var settingsItems: [Item] = []
    private(set) var recents: [Item] = []
    private(set) var actions: [Item] = []
    private(set) var index = SearchIndex(items: [])
    private(set) var habits = HabitModel(openings: [], now: Date())
    private(set) var forgotten: Set<String> = []
    private(set) var openingCount = 0
    /// Acces a Documents, Bureau et Telechargements (carte d'accueil).
    var folderAccess: FolderAccess.State {
        didSet { defaults.set(folderAccess.rawValue, forKey: Brand.key("FolderAccess")) }
    }
    /// Carte d'accueil : acces jamais demande, et aucun fichier recent de ces dossiers (Spotlight les cache).
    var needsFolderAccess: Bool {
        switch folderAccess {
        case .denied: true
        case .unknown: useRecents && recentsLoaded && !recents.contains { FolderAccess.covers($0.target) }
        case .granted, .dismissed: false
        }
    }
    private(set) var recentsLoaded = false
    /// Raccourci systeme qui passe avant celui de Lanterne, s'il y en a un.
    private(set) var conflict: SymbolicHotKey?
    private(set) var spotlightShortcutEnabled = true
    @ObservationIgnored private var appSignature: [String: Date] = [:]
    @ObservationIgnored private var indexGeneration = Generation()
    @ObservationIgnored private var recentFiles: RecentFiles?
    @ObservationIgnored private let spotlight = SpotlightSearch()
    @ObservationIgnored private var furtherTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Mode capture : apps du systeme seulement, fichiers d'exemple, pas de requete vivante.
    @ObservationIgnored var demo = false

    // MARK: Panneau

    var query = "" { didSet { if query != oldValue { search() } } }
    private(set) var sections: [ResultSection] = []
    private(set) var further: ResultSection?
    private(set) var selectedKey: String?
    var hoveredKey: String?
    private(set) var context = SearchContext(contextApp: nil)
    private(set) var panelOpenCount = 0
    /// Message passager du pied du panneau ("Chemin copie").
    private(set) var notice: String?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private(set) var panel: FloatingPanelController<AnyView>?
    #if DEBUG
    @ObservationIgnored private var latencies: [Double] = []
    #endif

    /// Lignes dans l'ordre affiche (Cmd-1 a Cmd-9, fleches).
    var rows: [Ranked] { sections.flatMap(\.items) + (further?.items ?? []) }
    var selected: Ranked? { rows.first { $0.id == selectedKey } ?? rows.first }

    var exclusions: Exclusions {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let types = excludedTypes.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }.filter { !$0.isEmpty }
        return Exclusions(folders: Exclusions.defaultFolders(home: home) + excludedFolders, extensions: Set(types),
                          forgotten: forgotten)
    }

    private init() {
        do {
            database = try AppDatabase.open()
        } catch {
            fatalError("Impossible d'ouvrir la base \(AppDatabase.defaultURL.path) : \(error)")
        }
        store = HabitStore(database)
        let d = UserDefaults.standard
        func flag(_ key: String) -> Bool { d.object(forKey: Brand.key(key)) as? Bool ?? true }
        learningPaused = d.bool(forKey: Brand.key("LearningPaused"))
        let days = d.integer(forKey: Brand.key("MemoryDays"))
        memoryDays = Self.memoryChoices.contains(days) ? days : 365
        useApps = flag("SourceApps")
        useSettings = flag("SourceSettings")
        useRecents = flag("SourceRecents")
        useSpotlight = flag("SourceSpotlight")
        useActions = flag("SourceActions")
        excludedFolders = d.stringArray(forKey: Brand.key("ExcludedFolders")) ?? []
        excludedTypes = d.string(forKey: Brand.key("ExcludedTypes")) ?? ""
        folderAccess = FolderAccess.State(rawValue: d.string(forKey: Brand.key("FolderAccess")) ?? "") ?? .unknown
        reloadHabits()
    }

    private func saveSource(_ on: Bool, _ name: String) { defaults.set(on, forKey: Brand.key("Source" + name)) }

    // MARK: Demarrage et sources

    func start() {
        purge()
        reloadSources()
        refreshConflicts()
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: HubManifest.appsChangedNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppState.shared.reloadActions() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                               queue: .main) { _ in
            MainActor.assumeIsolated { AppState.shared.refreshConflicts() }
        })
    }

    /// Relit apps, reglages, actions ; lance ou arrete la requete des fichiers recents.
    func reloadSources() {
        let demo = self.demo
        let useApps = self.useApps, useSettings = self.useSettings
        Task {
            async let appsScan = Task.detached { useApps ? AppIndex.scan(systemOnly: demo) : [] }.value
            async let settingsScan = Task.detached { useSettings ? SettingsIndex.load() : (items: [], extensionPaths: [:]) }.value
            let (foundApps, foundSettings) = await (appsScan, settingsScan)
            self.apps = demo ? foundApps + Self.demoExtraApps() : foundApps
            self.settingsItems = foundSettings.items
            for (key, path) in foundSettings.extensionPaths { Icons.paths[key] = path }
            self.appSignature = AppIndex.signature(systemOnly: demo)
            self.reloadActions()
        }
        if useRecents && !demo {
            if recentFiles == nil {
                recentFiles = RecentFiles { items in
                    AppState.shared.recents = items
                    AppState.shared.recentsLoaded = true
                    AppState.shared.rebuildIndex()
                }
                recentFiles?.start()
            }
        } else {
            recentFiles?.stop()
            recentFiles = nil
            if !demo { recents = [] }
        }
    }

    /// Demande l'acces aux trois dossiers (une demande de macOS par dossier), puis relance les fichiers recents.
    func requestFolderAccess() {
        Task {
            let granted = await Task.detached { FolderAccess.request() }.value
            self.folderAccess = granted ? .granted : .denied
            self.recentFiles?.stop()
            self.recentFiles = nil
            self.reloadSources()
        }
    }

    #if DEBUG
    /// Carte d'acces aux dossiers visible ou non (mode capture), sans rien ecrire dans les preferences.
    func debugShowFolderAccessCard(_ shown: Bool) { recentsLoaded = shown }
    #endif

    func reloadActions() {
        if useActions && !demo {
            let found = VialetActions.load(excluding: Brand.identity.bundleIdentifier)
            actions = found.items
            for (key, path) in found.appPaths { Icons.paths[key] = path }
        } else {
            actions = []
        }
        rebuildIndex()
    }

    /// Reconstruit l'index (hors fil principal) ; les fichiers exclus n'y entrent pas.
    func rebuildIndex() {
        let exclusions = self.exclusions
        let items = (apps + settingsItems + actions + recents).filter { !exclusions.excludes($0) }
        let ticket = indexGeneration.next()
        Task {
            let built = await Task.detached { SearchIndex(items: items) }.value
            // Un index construit avant une demande plus recente (oubli, exclusion) ne l'ecrase jamais.
            guard self.indexGeneration.accept(ticket) else { return }
            self.index = built
            if self.panel?.isVisible == true || self.demo { self.search(keepSelection: true) }
        }
    }

    /// Apps : nouveau parcours si un dossier d'applications a change.
    private func refreshAppsIfNeeded() {
        guard useApps, AppIndex.signature(systemOnly: demo) != appSignature else { return }
        reloadSources()
    }

    func refreshConflicts() {
        let table = ShortcutConflicts.table()
        conflict = ShortcutConflicts.conflict(for: HotKeyController.shared.shortcut, in: table)
        spotlightShortcutEnabled = SymbolicHotKeys.isSpotlightEnabled(table)
    }

    // MARK: Habitudes

    func reloadHabits() {
        let openings = (try? store.openings()) ?? []
        habits = HabitModel(openings: openings, now: Date())
        openingCount = openings.count
        forgotten = (try? store.forgotten()) ?? []
    }

    func purge() {
        try? store.purge(now: Date(), keepDays: memoryDays)
    }

    func record(_ item: Item) {
        guard !learningPaused else { return }
        _ = try? store.record(Opening(item: item, at: Date(), contextApp: context.contextApp, query: query))
        reloadHabits()
    }

    func forget(_ key: String) {
        try? store.forget(key)
        reloadHabits()
        rebuildIndex()
    }

    func unforget(_ key: String) {
        try? store.unforget(key)
        reloadHabits()
        rebuildIndex()
    }

    func eraseAll() {
        try? store.eraseAll()
        reloadHabits()
        rebuildIndex()
    }

    /// Element connu de l'index, ou reconstruit depuis sa cle (fichier toujours present).
    func orphan(_ profile: HabitProfile) -> Item? {
        guard let path = Item.path(fromKey: profile.key), FileManager.default.fileExists(atPath: path) else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return Item(key: profile.key, title: profile.title,
                    subtitle: RecentFiles.abbreviate((path as NSString).deletingLastPathComponent, home: home),
                    kind: profile.kind, target: path)
    }

    /// Titre lisible d'une cle (liste des oublis).
    func title(forKey key: String) -> String {
        if let item = index.item(forKey: key) { return item.title }
        if let path = Item.path(fromKey: key) { return (path as NSString).lastPathComponent }
        if key.hasPrefix("app:") { return AppNames.name(for: String(key.dropFirst(4))) ?? String(key.dropFirst(4)) }
        return key.split(separator: ":", maxSplits: 1).last.map(String.init) ?? key
    }

    /// Raison d'une ligne : lettres deja tapees pour cet element, sinon la phrase des habitudes.
    func reason(for key: String) -> String? {
        let q = SearchQuery(query)
        if !q.isEmpty {
            let n = habits.prefixCount(key: key, query: q)
            if n >= 2 { return "Choisi \(n) fois apr\u{00E8}s \u{00AB}\u{00A0}\(q.normalized)\u{00A0}\u{00BB}" }
        }
        return habits.explain(key: key, now: Date()) { AppNames.name(for: $0) }
    }

    // MARK: Recherche

    func search(keepSelection: Bool = false) {
        #if DEBUG
        let started = DispatchTime.now().uptimeNanoseconds
        #endif
        let q = SearchQuery(query)
        let previous = selectedKey
        furtherTask?.cancel()
        spotlight.cancel()
        further = nil
        if q.isEmpty {
            let items = index.suggestions(habits: habits, context: context, exclusions: exclusions, limit: 8) { self.orphan($0) }
            sections = items.isEmpty ? [] : [ResultSection(kind: .suggestions, items: items)]
        } else {
            sections = index.search(q, habits: habits, context: context, exclusions: exclusions)
            if useSpotlight && q.count >= 2 && !demo { scheduleFurther(q) }
        }
        selectedKey = keepSelection && rows.contains(where: { $0.id == previous }) ? previous : rows.first?.id
        #if DEBUG
        let ms = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        if !q.isEmpty { latencies.append(ms) }
        NSLog("Lanterne frappe : %.2f ms (%d car., %d lignes, index %d)", ms, q.count, rows.count, index.count)
        #endif
    }

    private func scheduleFurther(_ q: SearchQuery) {
        let raw = query
        furtherTask = Task {
            try? await Task.sleep(for: SpotlightSearch.delay)
            guard !Task.isCancelled, self.query == raw else { return }
            self.spotlight.search(raw.trimmingCharacters(in: .whitespaces)) { found, _ in
                guard self.query == raw, !found.isEmpty else { return }
                let shown = Set(self.sections.flatMap { $0.items.map(\.id) })
                self.further = self.index.further(found, query: q, shown: shown, exclusions: self.exclusions)
                if self.selectedKey == nil { self.selectedKey = self.rows.first?.id }
            }
        }
    }

    /// Donne des resultats "Plus loin" (mode capture).
    func setFurther(_ items: [Item]) {
        let shown = Set(sections.flatMap { $0.items.map(\.id) })
        further = index.further(items, query: SearchQuery(query), shown: shown, exclusions: exclusions)
    }

    func moveSelection(by delta: Int) {
        let rows = self.rows
        guard !rows.isEmpty else { return }
        let i = rows.firstIndex { $0.id == selectedKey } ?? 0
        selectedKey = rows[min(max(0, i + delta), rows.count - 1)].id
    }

    func select(_ key: String) { selectedKey = key }

    // MARK: Actions du panneau

    /// Texte du panneau pour un resultat qui ne s'ouvre pas directement.
    static let guardedNotice = "Script : montr\u{00E9} dans le Finder"

    func open(_ ranked: Ranked) {
        if Launcher.isGuarded(ranked.item) {
            Launcher.reveal(ranked.item)
            flash(Self.guardedNotice)
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                self.hidePanel()
            }
            return
        }
        guard Launcher.open(ranked.item) else {
            flash("Introuvable : \(ranked.item.title)")
            return
        }
        record(ranked.item)
        hidePanel()
    }

    func openSelected() { if let s = selected { open(s) } }

    /// Cmd-1 a Cmd-9.
    func open(number: Int) {
        let rows = self.rows
        guard number >= 1, number <= min(9, rows.count) else { return }
        open(rows[number - 1])
    }

    func revealSelected() {
        guard let s = selected else { return }
        if Launcher.reveal(s.item) { hidePanel() } else { flash("Rien \u{00E0} montrer dans le Finder") }
    }

    func copySelectedPath() {
        guard let s = selected else { return }
        Launcher.copyPath(s.item)
        flash(s.item.kind == .setting || s.item.kind == .action ? "Lien copi\u{00E9}" : "Chemin copi\u{00E9}")
    }

    func forgetSelected() {
        guard let s = selected else { return }
        forget(s.item.key)
        flash("\u{00AB}\u{00A0}\(s.item.title)\u{00A0}\u{00BB} oubli\u{00E9}")
        search(keepSelection: false)
    }

    private func flash(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled { self.notice = nil }
        }
    }

    // MARK: Panneau

    func togglePanel() {
        if panel?.isVisible == true { hidePanel() } else { showPanel() }
    }

    /// `forced` : contexte impose (mode capture) ; sinon l'heure courante et l'app au premier plan.
    func showPanel(context forced: SearchContext? = nil) {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        context = forced ?? SearchContext(contextApp: front == Brand.identity.bundleIdentifier ? context.contextApp : front)
        let panel = self.panel ?? FloatingPanelController(size: Self.panelSize) {
            AnyView(SearchPanel().environment(AppState.shared))
        }
        self.panel = panel
        refreshAppsIfNeeded()
        reloadHabits()
        hoveredKey = nil
        if query.isEmpty { search() } else { query = "" }
        panelOpenCount += 1
        panel.show()
    }

    func hidePanel() {
        panel?.hide()
        furtherTask?.cancel()
        spotlight.cancel()
        #if DEBUG
        if !latencies.isEmpty {
            let sorted = latencies.sorted()
            NSLog("Lanterne latence par frappe : %d frappes, mediane %.2f ms, p95 %.2f ms, max %.2f ms", sorted.count,
                  sorted[sorted.count / 2], sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], sorted.last!)
            latencies = []
        }
        #endif
    }

    // MARK: Mode capture

    #if DEBUG
    func debugSetConflict(_ conflict: SymbolicHotKey?) { self.conflict = conflict }
    #endif

    func setDemoFiles(_ items: [Item]) {
        recents = items
        rebuildIndex()
    }

    /// Safari n'est pas dans /System/Applications : ajoutee au mode capture.
    nonisolated static func demoExtraApps() -> [Item] {
        ["/Applications/Safari.app"].compactMap { FileManager.default.fileExists(atPath: $0) ? AppIndex.item(at: $0) : nil }
    }
}

/// Nom affiche d'une app a partir de son identifiant de bundle (cache).
@MainActor
enum AppNames {
    private static var cache: [String: String?] = [:]

    static func name(for bundleId: String) -> String? {
        if let cached = cache[bundleId] { return cached }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId).map {
            let n = FileManager.default.displayName(atPath: $0.path)
            return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
        }
        cache[bundleId] = name
        return name
    }
}
