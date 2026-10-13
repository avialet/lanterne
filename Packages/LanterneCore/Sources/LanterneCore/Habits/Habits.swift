import Foundation

/// Une ouverture par Lanterne : quoi, quand (heure et jour locaux), depuis quelle app, apres quelles lettres.
public struct Opening: Sendable, Equatable {
    public var id: Int64?
    public let itemKey: String
    public let title: String
    public let kind: ItemKind
    public let openedAt: Date
    /// Heure locale 0-23.
    public let hour: Int
    /// Jour de la semaine (1 = dimanche, calendrier gregorien).
    public let weekday: Int
    /// Bundle de l'app au premier plan au moment du raccourci.
    public let contextApp: String?
    /// Requete normalisee, 12 caracteres au plus ; vide si l'element a ete ouvert depuis le champ vide.
    public let prefix: String

    public static let maxPrefixLength = 12

    public init(id: Int64? = nil, itemKey: String, title: String, kind: ItemKind, openedAt: Date, hour: Int,
                weekday: Int, contextApp: String?, prefix: String) {
        self.id = id
        self.itemKey = itemKey
        self.title = title
        self.kind = kind
        self.openedAt = openedAt
        self.hour = hour
        self.weekday = weekday
        self.contextApp = contextApp
        self.prefix = prefix
    }

    public init(item: Item, at date: Date, contextApp: String?, query: String, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .weekday], from: date)
        self.init(itemKey: item.key, title: item.title, kind: item.kind, openedAt: date, hour: parts.hour ?? 0,
                  weekday: parts.weekday ?? 1, contextApp: contextApp,
                  prefix: String(SearchQuery(query).normalized.prefix(Self.maxPrefixLength)))
    }
}

/// Ce que Lanterne sait d'un element, tire de ses ouvertures.
public struct HabitProfile: Sendable {
    public let key: String
    /// Titre et genre de l'ouverture la plus recente.
    public internal(set) var title: String
    public internal(set) var kind: ItemKind
    public internal(set) var count = 0
    /// Ouvertures amorties (demi-vie `HabitModel.halfLife`).
    public internal(set) var decayed: Double = 0
    public internal(set) var weekCount = 0
    public internal(set) var lastOpened: Date
    /// Ouvertures par heure (brutes, pour la bande des 24 heures et les phrases).
    public internal(set) var hourCounts = [Int](repeating: 0, count: 24)
    /// Ouvertures amorties par heure.
    var hourWeights = [Double](repeating: 0, count: 24)
    var contextCounts: [String: Int] = [:]
    var contextWeights: [String: Double] = [:]
    /// Prefixe tape -> (poids amorti, nombre).
    var prefixes: [String: (weight: Double, count: Int)] = [:]

    init(key: String, title: String, kind: ItemKind, lastOpened: Date) {
        self.key = key
        self.title = title
        self.kind = kind
        self.lastOpened = lastOpened
    }

    /// Affinite horaire : 1 = sans preference ; au-dela, cette heure est habituelle. Heures lissees a +-1 h
    /// (0,25 / 0,5 / 0,25), a priori uniforme de poids 2.
    public func hourAffinity(_ hour: Int) -> Double {
        let h = ((hour % 24) + 24) % 24
        let smoothed = 0.25 * hourWeights[(h + 23) % 24] + 0.5 * hourWeights[h] + 0.25 * hourWeights[(h + 1) % 24]
        let total = hourWeights.reduce(0, +)
        let prior = 2.0
        return (smoothed + prior / 24) / ((total + prior) / 24)
    }

    /// Apps d'origine les plus frequentes (bundle, nombre).
    public func topContexts(limit: Int) -> [(bundle: String, count: Int)] {
        contextCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit).map { ($0.key, $0.value) }
    }
}

/// Part des habitudes dans le classement : generale (frequence, heure, app d'origine) et lettres tapees.
public struct HabitBoost: Sendable, Equatable {
    public let general: Double
    public let prefix: Double
    public var total: Double { general + prefix }
    public static let zero = HabitBoost(general: 0, prefix: 0)
}

/// Habitudes calculees a partir des ouvertures, par simple comptage : frequence amortie (demi-vie 14 j),
/// affinite horaire, affinite a l'app d'origine, affinite aux lettres tapees (le signal fort).
public struct HabitModel: Sendable {
    public static let halfLife: TimeInterval = 14 * 86400
    public let profiles: [String: HabitProfile]

    public init(openings: [Opening], now: Date, halfLife: TimeInterval = HabitModel.halfLife) {
        var profiles: [String: HabitProfile] = [:]
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        for o in openings.sorted(by: { $0.openedAt < $1.openedAt }) {
            let age = max(0, now.timeIntervalSince(o.openedAt))
            let weight = pow(0.5, age / halfLife)
            var p = profiles[o.itemKey] ?? HabitProfile(key: o.itemKey, title: o.title, kind: o.kind, lastOpened: o.openedAt)
            p.title = o.title
            p.kind = o.kind
            p.lastOpened = o.openedAt
            p.count += 1
            p.decayed += weight
            if o.openedAt > weekAgo { p.weekCount += 1 }
            let h = min(max(o.hour, 0), 23)
            p.hourCounts[h] += 1
            p.hourWeights[h] += weight
            if let app = o.contextApp {
                p.contextCounts[app, default: 0] += 1
                p.contextWeights[app, default: 0] += weight
            }
            if !o.prefix.isEmpty {
                let old = p.prefixes[o.prefix] ?? (0, 0)
                p.prefixes[o.prefix] = (old.weight + weight, old.count + 1)
            }
            profiles[o.itemKey] = p
        }
        self.profiles = profiles
    }

    /// Profils du plus habituel au moins habituel (frequence amortie, puis titre).
    public var ordered: [HabitProfile] {
        profiles.values.sorted { $0.decayed != $1.decayed ? $0.decayed > $1.decayed : $0.title < $1.title }
    }

    public func boost(key: String, query: SearchQuery, hour: Int, contextApp: String?) -> HabitBoost {
        guard let p = profiles[key] else { return .zero }
        let hourFactor = min(max(p.hourAffinity(hour), 0.3), 3).squareRoot()
        var contextShare = 0.0
        if let contextApp, let w = p.contextWeights[contextApp] { contextShare = w / (p.decayed + 1) }
        let general = 0.6 * log1p(p.decayed) * hourFactor * (1 + contextShare)
        var prefixWeight = 0.0
        let q = query.normalized
        if !q.isEmpty {
            for (prefix, value) in p.prefixes {
                if prefix == q { prefixWeight += value.weight }
                else if prefix.hasPrefix(q) { prefixWeight += 0.5 * value.weight }
                else if q.hasPrefix(prefix) { prefixWeight += 0.35 * value.weight }
            }
        }
        return HabitBoost(general: general, prefix: 1.2 * log1p(prefixWeight))
    }

    /// Nombre d'ouvertures apres exactement ces lettres.
    public func prefixCount(key: String, query: SearchQuery) -> Int {
        profiles[key]?.prefixes[String(query.normalized.prefix(Opening.maxPrefixLength))]?.count ?? 0
    }

    /// Phrase de raison : "12 fois cette semaine, souvent vers 9 h depuis Mail".
    public func explain(key: String, now: Date, appName: (String) -> String?) -> String? {
        guard let p = profiles[key], p.count > 0 else { return nil }
        var text: String
        if p.weekCount > 0 {
            text = p.weekCount == 1 ? "Une fois cette semaine" : "\(p.weekCount) fois cette semaine"
        } else {
            let days = max(1, Int(now.timeIntervalSince(p.lastOpened) / 86400))
            let ago = days == 1 ? "hier" : "il y a \(days) jours"
            text = p.count == 1 ? "Une fois, \(ago)" : "\(p.count) fois, la derni\u{00E8}re \(ago)"
        }
        var when: String?
        if p.count >= 3 {
            let total = Double(p.count)
            if let mode = p.hourCounts.indices.max(by: { p.hourCounts[$0] < p.hourCounts[$1] }),
               Double(p.hourCounts[mode]) / total >= 0.6 {
                when = "souvent vers \(mode) h"
            } else {
                var periods: [DayPeriod: Int] = [:]
                for (hour, count) in p.hourCounts.enumerated() { periods[DayPeriod(hour: hour), default: 0] += count }
                if let top = periods.max(by: { $0.value < $1.value }), Double(top.value) / total >= 0.6 {
                    when = "surtout " + top.key.phrase
                }
            }
        }
        if let when { text += ", " + when }
        if p.count >= 3, let top = p.topContexts(limit: 1).first, Double(top.count) / Double(p.count) >= 0.5,
           let name = appName(top.bundle) {
            text += (when == nil ? ", depuis " : " depuis ") + name
        }
        return text
    }
}

/// Moments de la journee des phrases de raison.
enum DayPeriod: Hashable {
    case morning, noon, afternoon, evening, night

    init(hour: Int) {
        switch hour {
        case 5..<12: self = .morning
        case 12..<14: self = .noon
        case 14..<18: self = .afternoon
        case 18..<23: self = .evening
        default: self = .night
        }
    }

    var phrase: String {
        switch self {
        case .morning: "le matin"
        case .noon: "\u{00E0} midi"
        case .afternoon: "l'apr\u{00E8}s-midi"
        case .evening: "le soir"
        case .night: "la nuit"
        }
    }
}
