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

    public init(kind: ResultSectionKind, items: [Ranked]) {
        self.kind = kind
        self.items = items
    }
}

/// Index en memoire et classement : `score = correspondance x (1 + habitudes + a priori)`.
/// Les habitudes generales sont plafonnees selon le palier (une sous-sequence ne monte pas au-dessus
/// d'un debut de nom par la seule frequence) ; les lettres deja tapees pour cet element ne le sont pas.
public final class SearchIndex: Sendable {
    struct Entry: Sendable {
        let item: Item
        let text: SearchText
    }

    /// Candidat leger pendant le classement (indice dans `entries`).
    struct Candidate {
        let index: Int
        let score: Double
        let boost: HabitBoost
    }

    let entries: [Entry]
    private let positions: [String: Int]
    /// Tableaux paralleles a `entries`, parcourus sans copier les elements : masque des lettres, section,
    /// longueur du titre.
    private let masks: [UInt64]
    private let sections: [Int]
    private let titleLengths: [Int]
    /// Premiere lettre de chaque mot du titre -> elements (requete d'une lettre).
    private let initials: [UInt32: [Int]]

    static let searchSections: [ResultSectionKind] = [.apps, .settings, .files, .actions]

    public init(items: [Item]) {
        var seen = Set<String>()
        var entries: [Entry] = []
        entries.reserveCapacity(items.count)
        for item in items where seen.insert(item.key).inserted {
            entries.append(Entry(item: item, text: SearchText(item.title, keywords: item.keywords)))
        }
        self.entries = entries
        var positions: [String: Int] = [:]
        var initials: [UInt32: [Int]] = [:]
        for (i, e) in entries.enumerated() {
            positions[e.item.key] = i
            for letter in Set(e.text.wordStarts.map { e.text.scalars[$0] }) { initials[letter, default: []].append(i) }
        }
        self.positions = positions
        self.initials = initials
        masks = entries.map(\.text.mask)
        sections = entries.map { Self.searchSections.firstIndex(of: ResultSectionKind.of($0.item.kind)) ?? 0 }
        titleLengths = entries.map { $0.item.title.count }
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

    /// Resultats regroupes : le meilleur d'abord, puis apps, reglages, fichiers et actions (ordre fixe).
    /// Chaque section garde ses `limits` meilleurs ; les plages de surlignage ne sont calculees que pour eux.
    public func search(_ query: SearchQuery, habits: HabitModel, context: SearchContext, exclusions: Exclusions,
                       limits: Limits = Limits()) -> [ResultSection] {
        guard !query.isEmpty else { return [] }
        var learned = [Bool](repeating: false, count: entries.count)
        for key in habits.profiles.keys { if let i = positions[key] { learned[i] = true } }
        let caps = Self.searchSections.map { limits.limit($0) + 1 }
        var buckets = [[Candidate]](repeating: [], count: caps.count)
        let qmask = query.mask

        func consider(_ i: Int) {
            guard masks[i] & qmask == qmask, let match = Matcher.match(query, entries[i].text, withRanges: false) else { return }
            var boost = HabitBoost.zero
            if learned[i] && !exclusions.forgotten.contains(entries[i].item.key) {
                boost = habits.boost(key: entries[i].item.key, query: query, hour: context.hour, contextApp: context.contextApp)
            }
            let general = min(boost.general, Self.cap(match.tier))
            let score = match.score * (1 + general + boost.prefix + Self.prior(entries[i].item, now: context.now))
            let candidate = Candidate(index: i, score: score, boost: boost)
            let b = sections[i]
            if buckets[b].count == caps[b], let last = buckets[b].last, !better(candidate, last) { return }
            guard !exclusions.excludes(entries[i].item) else { return }
            let at = buckets[b].firstIndex { better(candidate, $0) } ?? buckets[b].count
            buckets[b].insert(candidate, at: at)
            if buckets[b].count > caps[b] { buckets[b].removeLast() }
        }

        if query.count == 1 {
            for i in initials[query.scalars[0]] ?? [] { consider(i) }
        } else {
            for i in 0..<entries.count { consider(i) }
        }

        guard let best = buckets.compactMap(\.first).min(by: better) else { return [] }
        var result = [ResultSection(kind: .best, items: [ranked(best, query)])]
        for (b, kind) in Self.searchSections.enumerated() {
            let items = buckets[b].filter { $0.index != best.index }.prefix(limits.limit(kind))
            if !items.isEmpty { result.append(ResultSection(kind: kind, items: items.map { ranked($0, query) })) }
        }
        return result
    }

    private func ranked(_ c: Candidate, _ query: SearchQuery) -> Ranked {
        Ranked(item: entries[c.index].item, score: c.score, match: Matcher.match(query, entries[c.index].text), boost: c.boost)
    }

    /// Meme ordre que `order`, longueurs de titre precalculees.
    private func better(_ a: Candidate, _ b: Candidate) -> Bool {
        if a.score != b.score { return a.score > b.score }
        if titleLengths[a.index] != titleLengths[b.index] { return titleLengths[a.index] < titleLengths[b.index] }
        let ta = entries[a.index].item.title, tb = entries[b.index].item.title
        if ta != tb { return ta < tb }
        return entries[a.index].item.key < entries[b.index].item.key
    }

    /// Champ vide : ce qu'on ouvre d'habitude a cette heure et depuis cette app, puis, a froid, les elements
    /// recemment utilises d'apres Spotlight. `orphan` reconstruit un element appris absent de l'index
    /// (fichier ouvert depuis "Plus loin") ou renvoie nil s'il n'existe plus.
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
