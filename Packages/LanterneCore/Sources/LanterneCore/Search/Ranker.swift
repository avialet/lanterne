import Foundation

/// Moment et contexte d'une recherche : heure locale et app au premier plan au moment du raccourci.
public struct SearchContext: Sendable, Equatable {
    public let now: Date
    public let hour: Int
    public let contextApp: String?

    public init(now: Date, hour: Int, contextApp: String?) {
        self.now = now
        self.hour = hour
        self.contextApp = contextApp
    }

    public init(now: Date = Date(), contextApp: String?, calendar: Calendar = .current) {
        self.init(now: now, hour: calendar.component(.hour, from: now), contextApp: contextApp)
    }
}

/// Ce que Lanterne ne montre pas : dossiers et extensions exclus (fichiers), elements oublies.
/// Toujours exclus : `node_modules`, chemins caches (un composant commencant par un point).
public struct Exclusions: Sendable, Equatable {
    /// Chemins absolus, sans barre finale.
    public var folders: [String]
    /// Extensions en minuscules, sans point.
    public var extensions: Set<String>
    /// Cles oubliees : fichiers, dossiers et actions disparaissent ; apps et reglages restent trouvables,
    /// sans habitudes ni suggestion.
    public var forgotten: Set<String>

    public init(folders: [String] = [], extensions: Set<String> = [], forgotten: Set<String> = []) {
        self.folders = folders.map { $0.hasSuffix("/") && $0.count > 1 ? String($0.dropLast()) : $0 }
        self.extensions = Set(extensions.map { $0.lowercased() })
        self.forgotten = forgotten
    }

    /// `~/Library` : caches et donnees d'apps, jamais utiles dans un lanceur.
    public static func defaultFolders(home: String) -> [String] {
        [(home as NSString).appendingPathComponent("Library")]
    }

    public func excludes(path: String) -> Bool {
        if path.contains("/node_modules/") || path.contains("/.") { return true }
        for folder in folders where path == folder || path.hasPrefix(folder + "/") { return true }
        if !extensions.isEmpty {
            let ext = (path as NSString).pathExtension.lowercased()
            if !ext.isEmpty && extensions.contains(ext) { return true }
        }
        return false
    }

    public func excludes(_ item: Item) -> Bool {
        switch item.kind {
        case .file, .folder:
            return forgotten.contains(item.key) || excludes(path: item.target)
        case .action:
            return forgotten.contains(item.key)
        case .app, .setting:
            return false
        }
    }
}

/// Un resultat classe.
public struct Ranked: Sendable, Identifiable {
    public let item: Item
    public let score: Double
    public let match: Match?
    public let boost: HabitBoost
    public var id: String { item.key }
}

public enum ResultSectionKind: String, Sendable, CaseIterable {
    case suggestions, best, apps, settings, files, actions, further

    public var title: String {
        switch self {
        case .suggestions: "Pour vous maintenant"
        case .best: "Meilleur r\u{00E9}sultat"
        case .apps: "Apps"
        case .settings: "R\u{00E9}glages"
        case .files: "Fichiers et dossiers"
        case .actions: "Actions"
        case .further: "Plus loin"
        }
    }

    static func of(_ kind: ItemKind) -> ResultSectionKind {
        switch kind {
        case .app: .apps
        case .setting: .settings
        case .file, .folder: .files
        case .action: .actions
        }
    }
}

public struct ResultSection: Sendable, Identifiable {
    public let kind: ResultSectionKind
    public let items: [Ranked]
    public var id: String { kind.rawValue }
}

/// Index en memoire et classement : `score = correspondance x (1 + habitudes + a priori)`.
/// Les habitudes generales sont plafonnees selon le palier (une sous-sequence ne monte pas au-dessus
/// d'un debut de nom par la seule frequence) ; les lettres deja tapees pour cet element ne le sont pas.
public final class SearchIndex: Sendable {
    struct Entry: Sendable {
        let item: Item
        let text: SearchText
    }

    let entries: [Entry]
    private let positions: [String: Int]

    public init(items: [Item]) {
        var seen = Set<String>()
        var entries: [Entry] = []
        entries.reserveCapacity(items.count)
        for item in items where seen.insert(item.key).inserted {
            entries.append(Entry(item: item, text: SearchText(item.title, keywords: item.keywords)))
        }
        self.entries = entries
        var positions: [String: Int] = [:]
        for (i, e) in entries.enumerated() { positions[e.item.key] = i }
        self.positions = positions
    }

    public var count: Int { entries.count }
    public var items: [Item] { entries.map(\.item) }

    public func item(forKey key: String) -> Item? {
        positions[key].map { entries[$0].item }
    }

    /// Nombre de resultats par section.
    public struct Limits: Sendable {
        public var apps = 5, settings = 4, files = 5, actions = 3
        public init() {}
        func limit(_ kind: ResultSectionKind) -> Int {
            switch kind {
            case .apps: apps
            case .settings: settings
            case .files: files
            case .actions: actions
            default: 1
            }
        }
    }

    public func search(_ query: SearchQuery, habits: HabitModel, context: SearchContext, exclusions: Exclusions,
                       limits: Limits = Limits()) -> [ResultSection] {
        guard !query.isEmpty else { return [] }
        var ranked: [Ranked] = []
        for entry in entries where entry.text.mayContain(query) {
            guard let match = Matcher.match(query, entry.text), !exclusions.excludes(entry.item) else { continue }
            let boost = exclusions.forgotten.contains(entry.item.key)
                ? .zero : habits.boost(key: entry.item.key, query: query, hour: context.hour, contextApp: context.contextApp)
            ranked.append(Self.rank(entry.item, match: match, boost: boost, now: context.now))
        }
        ranked.sort(by: Self.order)
        guard let best = ranked.first else { return [] }
        var sections = [ResultSection(kind: .best, items: [best])]
        for kind in [ResultSectionKind.apps, .settings, .files, .actions] {
            let items = ranked.dropFirst().filter { ResultSectionKind.of($0.item.kind) == kind }.prefix(limits.limit(kind))
            if !items.isEmpty { sections.append(ResultSection(kind: kind, items: Array(items))) }
        }
        return sections
    }

    /// Champ vide : ce qu'on ouvre d'habitude a cette heure et depuis cette app, puis, a froid, les elements
    /// recemment utilises d'apres Spotlight. `orphan` reconstruit un element appris absent de l'index
    /// (fichier ouvert depuis « Plus loin ») ou renvoie nil s'il n'existe plus.
    public func suggestions(habits: HabitModel, context: SearchContext, exclusions: Exclusions, limit: Int = 8,
                            orphan: (HabitProfile) -> Item?) -> [Ranked] {
        var ranked: [Ranked] = []
        var used = Set<String>()
        let empty = SearchQuery("")
        for profile in habits.profiles.values where !exclusions.forgotten.contains(profile.key) {
            guard let item = item(forKey: profile.key) ?? orphan(profile), !exclusions.excludes(item) else { continue }
            let boost = habits.boost(key: item.key, query: empty, hour: context.hour, contextApp: context.contextApp)
            ranked.append(Ranked(item: item, score: 1 + boost.general, match: nil, boost: boost))
            used.insert(item.key)
        }
        ranked.sort(by: Self.order)
        if ranked.count < limit {
            var cold: [Ranked] = []
            for entry in entries where !used.contains(entry.item.key) && !exclusions.forgotten.contains(entry.item.key) {
                let prior = Self.prior(entry.item, now: context.now)
                guard prior > 0, !exclusions.excludes(entry.item) else { continue }
                cold.append(Ranked(item: entry.item, score: prior, match: nil, boost: .zero))
            }
            cold.sort(by: Self.order)
            ranked += cold.prefix(limit - ranked.count)
        }
        return Array(ranked.prefix(limit))
    }

    /// Longue traine (Spotlight) : sans les elements deja indexes ou affiches, ni les exclus ; classee par
    /// correspondance puis a priori. Ne change jamais l'ordre des sections deja affichees.
    public func further(_ found: [Item], query: SearchQuery, shown: Set<String>, exclusions: Exclusions,
                        limit: Int = 6, now: Date = Date()) -> ResultSection? {
        var seen = Set<String>()
        var ranked: [Ranked] = []
        for item in found where positions[item.key] == nil && !shown.contains(item.key) && seen.insert(item.key).inserted {
            guard !exclusions.excludes(item) else { continue }
            let match = Matcher.match(query, SearchText(item.title, keywords: item.keywords))
            ranked.append(Ranked(item: item, score: (match?.score ?? 0.2) * (1 + Self.prior(item, now: now)),
                                 match: match, boost: .zero))
        }
        guard !ranked.isEmpty else { return nil }
        ranked.sort(by: Self.order)
        return ResultSection(kind: .further, items: Array(ranked.prefix(limit)))
    }

    // MARK: Score

    static func rank(_ item: Item, match: Match, boost: HabitBoost, now: Date) -> Ranked {
        let general = min(boost.general, cap(match.tier))
        let score = match.score * (1 + general + boost.prefix + prior(item, now: now))
        return Ranked(item: item, score: score, match: match, boost: boost)
    }

    /// Plafond des habitudes generales selon le palier de correspondance.
    static func cap(_ tier: MatchTier) -> Double {
        switch tier {
        case .exact, .prefix, .wordStart: 4
        case .acronym: 3
        case .substring: 2
        case .tokens, .keyword: 1.5
        case .subsequence: 0.8
        }
    }

    /// A priori Spotlight (demarrage a froid) : derniere ouverture (decroissance sur 30 j) et nombre
    /// d'ouvertures ; 0 sans information.
    static func prior(_ item: Item, now: Date) -> Double {
        var prior = 0.0
        if let last = item.lastUsed {
            let days = max(0, now.timeIntervalSince(last) / 86400)
            prior += 0.25 * exp(-days / 30)
        }
        if item.useCount > 0 { prior += 0.15 * min(1, log1p(Double(item.useCount)) / log1p(50)) }
        return prior
    }

    /// Score decroissant, puis titre plus court, puis ordre alphabetique, puis cle : ordre stable.
    static func order(_ a: Ranked, _ b: Ranked) -> Bool {
        if a.score != b.score { return a.score > b.score }
        if a.item.title.count != b.item.title.count { return a.item.title.count < b.item.title.count }
        if a.item.title != b.item.title { return a.item.title < b.item.title }
        return a.item.key < b.item.key
    }
}
