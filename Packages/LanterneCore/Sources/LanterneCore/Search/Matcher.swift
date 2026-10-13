import Foundation

/// Texte cherchable (titre d'un element et ses mots-cles), normalise une fois pour toutes a l'indexation :
/// minuscules sans accents (`SearchNormalizer`), debuts de mots (espaces, ponctuation, camelCase) et
/// correspondance vers les caracteres d'origine pour le surlignage.
public struct SearchText: Sendable {
    public let original: String
    public let normalized: String
    let scalars: [UInt32]
    let wordStarts: [Int]
    /// Caractere d'origine de chaque scalaire normalise ; vide si identite (texte ASCII).
    let characterIndex: [Int32]
    let keywords: [Keyword]
    let mask: UInt64

    struct Keyword: Sendable {
        let scalars: [UInt32]
        let wordStarts: [Int]
    }

    public init(_ title: String, keywords: [String] = []) {
        original = title
        let folded = Self.fold(title)
        scalars = folded.scalars
        wordStarts = folded.wordStarts
        characterIndex = folded.map
        normalized = String(String.UnicodeScalarView(folded.scalars.compactMap(Unicode.Scalar.init)))
        var mask = Self.mask(folded.scalars)
        var list: [Keyword] = []
        list.reserveCapacity(keywords.count)
        for keyword in keywords {
            let k = Self.fold(keyword)
            guard !k.scalars.isEmpty else { continue }
            list.append(Keyword(scalars: k.scalars, wordStarts: k.wordStarts))
            mask |= Self.mask(k.scalars)
        }
        self.keywords = list
        self.mask = mask
    }

    /// Filtre rapide : toutes les lettres et chiffres de la requete figurent dans le titre ou les mots-cles.
    public func mayContain(_ query: SearchQuery) -> Bool {
        query.mask & ~mask == 0
    }

    // MARK: Normalisation

    struct Folded {
        var scalars: [UInt32] = []
        var wordStarts: [Int] = []
        var map: [Int32] = []
    }

    static func fold(_ text: String) -> Folded {
        var out = Folded()
        let isASCII = text.utf8.allSatisfy { $0 < 0x80 }
        var previousAlnum = false
        var previousLower = false
        if isASCII {
            out.scalars.reserveCapacity(text.utf8.count)
            for byte in text.utf8 {
                let upper = byte >= 65 && byte <= 90
                let lower = byte >= 97 && byte <= 122
                let digit = byte >= 48 && byte <= 57
                let alnum = upper || lower || digit
                let value = UInt32(upper ? byte + 32 : byte)
                if alnum && (!previousAlnum || (upper && previousLower)) { out.wordStarts.append(out.scalars.count) }
                out.scalars.append(value)
                previousAlnum = alnum
                previousLower = lower
            }
            return out
        }
        var offset: Int32 = 0
        for character in text {
            let folded = SearchNormalizer.normalize(String(character))
            let upper = character.isUppercase
            let lower = character.isLowercase
            let alnum = character.isLetter || character.isNumber
            var first = true
            for scalar in folded.unicodeScalars {
                if first && alnum && (!previousAlnum || (upper && previousLower)) { out.wordStarts.append(out.scalars.count) }
                out.scalars.append(Self.unifyPunctuation(scalar.value))
                out.map.append(offset)
                first = false
            }
            previousAlnum = alnum
            previousLower = lower
            offset += 1
        }
        return out
    }

    /// Apostrophe typographique et espace insecable ramenees a leur forme simple.
    static func unifyPunctuation(_ value: UInt32) -> UInt32 {
        switch value {
        case 0x2019, 0x2018: 0x27
        case 0xA0, 0x202F: 0x20
        case 0x2011, 0x2010: 0x2D
        default: value
        }
    }

    static func mask(_ scalars: [UInt32]) -> UInt64 {
        var mask: UInt64 = 0
        for s in scalars {
            if s >= 97 && s <= 122 { mask |= 1 << UInt64(s - 97) }
            else if s >= 48 && s <= 57 { mask |= 1 << UInt64(26 + s - 48) }
        }
        return mask
    }

    /// Plage de scalaires normalises -> plage de caracteres d'origine.
    func characterRange(_ range: Range<Int>) -> Range<Int> {
        guard !characterIndex.isEmpty else { return range }
        let lower = Int(characterIndex[range.lowerBound])
        let upper = Int(characterIndex[range.upperBound - 1]) + 1
        return lower..<upper
    }
}

/// Requete tapee, normalisee comme `SearchText` (espaces multiples reduits).
public struct SearchQuery: Sendable, Equatable {
    public let raw: String
    public let normalized: String
    let scalars: [UInt32]
    let tokens: [[UInt32]]
    let mask: UInt64

    public init(_ raw: String) {
        self.raw = raw
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let folded = SearchText.fold(collapsed)
        scalars = folded.scalars
        normalized = String(String.UnicodeScalarView(folded.scalars.compactMap(Unicode.Scalar.init)))
        tokens = scalars.split(separator: 0x20).map(Array.init)
        mask = SearchText.mask(folded.scalars)
    }

    public var isEmpty: Bool { scalars.isEmpty }
    public var count: Int { scalars.count }
}

/// Palier de correspondance, du plus faible au plus fort.
public enum MatchTier: Int, Comparable, Sendable {
    case subsequence, keyword, tokens, substring, acronym, wordStart, prefix, exact

    public static func < (a: MatchTier, b: MatchTier) -> Bool { a.rawValue < b.rawValue }
}

public struct Match: Equatable, Sendable {
    public let tier: MatchTier
    /// Entre 0 et 1 : le palier, puis la part du titre couverte.
    public let score: Double
    /// Caracteres du titre d'origine a surligner (vide pour un mot-cle).
    public let ranges: [Range<Int>]
}

/// Appariement d'une requete et d'un texte, par paliers : nom exact > debut du nom > debut de mot >
/// acronyme (« rs » : Reglages Systeme) > sous-chaine > mots dans le desordre > sous-sequence dense ;
/// mots-cles au debut d'un mot seulement. Une lettre seule ne trouve que des debuts de mots.
public enum Matcher {
    public static func match(_ query: SearchQuery, _ text: SearchText) -> Match? {
        guard !query.isEmpty, text.mayContain(query) else { return nil }
        let title = matchTitle(query, text)
        if let title, title.tier >= .acronym { return title }
        let keyword = matchKeywords(query, text)
        switch (title, keyword) {
        case let (t?, k?): return t.score >= k.score ? t : k
        case let (t?, nil): return t
        case let (nil, k?): return k
        default: return nil
        }
    }

    static func matchTitle(_ query: SearchQuery, _ text: SearchText) -> Match? {
        let q = query.scalars, t = text.scalars
        let n = q.count, m = t.count
        guard n > 0, m > 0 else { return nil }
        let coverage = n <= m ? Double(n) / Double(m) : 1
        func make(_ tier: MatchTier, _ base: Double, _ ranges: [Range<Int>]) -> Match {
            Match(tier: tier, score: min(1, base + 0.06 * coverage), ranges: merge(ranges.map(text.characterRange)))
        }
        if n <= m {
            if n == m && q == t { return Match(tier: .exact, score: 1, ranges: [text.characterRange(0..<m)]) }
            if hasPrefix(t, at: 0, q) { return make(.prefix, 0.9, [0..<n]) }
            for (index, start) in text.wordStarts.enumerated() where start > 0 && start + n <= m {
                if hasPrefix(t, at: start, q) {
                    return make(.wordStart, 0.78 - 0.01 * Double(min(index, 5)), [start..<start + n])
                }
            }
        }
        guard n >= 2 else { return nil }
        if query.tokens.count == 1, let ranges = acronym(q, text) { return make(.acronym, 0.68, ranges) }
        if n <= m, let start = find(t, q) { return make(.substring, 0.54, [start..<start + n]) }
        if query.tokens.count > 1, let ranges = tokens(query.tokens, text) { return make(.tokens, 0.46, ranges) }
        if query.tokens.count == 1, let (ranges, density) = subsequence(q, t) {
            return Match(tier: .subsequence, score: 0.24 + 0.2 * density, ranges: merge(ranges.map(text.characterRange)))
        }
        return nil
    }

    static func matchKeywords(_ query: SearchQuery, _ text: SearchText) -> Match? {
        let q = query.scalars
        guard q.count >= 2 else { return nil }
        var best: Double = 0
        for keyword in text.keywords where keyword.scalars.count >= q.count {
            if keyword.scalars.count == q.count && keyword.scalars == q { best = max(best, 0.56); break }
            for start in keyword.wordStarts where start + q.count <= keyword.scalars.count {
                if hasPrefix(keyword.scalars, at: start, q) { best = max(best, start == 0 ? 0.52 : 0.48); break }
            }
        }
        return best > 0 ? Match(tier: .keyword, score: best, ranges: []) : nil
    }

    // MARK: Paliers

    @inline(__always)
    static func hasPrefix(_ t: [UInt32], at start: Int, _ q: [UInt32]) -> Bool {
        if start + q.count > t.count { return false }
        var i = 0
        while i < q.count {
            if t[start + i] != q[i] { return false }
            i += 1
        }
        return true
    }

    static func find(_ t: [UInt32], _ q: [UInt32], from: Int = 0) -> Int? {
        guard q.count <= t.count - from else { return nil }
        let first = q[0]
        var i = from
        let last = t.count - q.count
        while i <= last {
            if t[i] == first && hasPrefix(t, at: i, q) { return i }
            i += 1
        }
        return nil
    }

    /// Initiales consecutives de mots : « rs » -> Reglages Systeme, « vsc » -> Visual Studio Code.
    static func acronym(_ q: [UInt32], _ text: SearchText) -> [Range<Int>]? {
        let starts = text.wordStarts
        guard starts.count >= q.count else { return nil }
        for first in 0...(starts.count - q.count) {
            var ok = true
            for j in 0..<q.count where text.scalars[starts[first + j]] != q[j] {
                ok = false
                break
            }
            if ok { return (0..<q.count).map { starts[first + $0]..<starts[first + $0] + 1 } }
        }
        return nil
    }

    /// Chaque mot de la requete, en debut de mot de preference, sinon n'importe ou.
    static func tokens(_ tokens: [[UInt32]], _ text: SearchText) -> [Range<Int>]? {
        var ranges: [Range<Int>] = []
        for token in tokens where !token.isEmpty {
            if let start = text.wordStarts.first(where: { hasPrefix(text.scalars, at: $0, token) }) {
                ranges.append(start..<start + token.count)
            } else if let start = find(text.scalars, token) {
                ranges.append(start..<start + token.count)
            } else {
                return nil
            }
        }
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// Sous-sequence la plus serree ; refusee si elle couvre plus de trois fois la longueur de la requete.
    static func subsequence(_ q: [UInt32], _ t: [UInt32]) -> ([Range<Int>], Double)? {
        var best: (start: Int, end: Int)?
        var i = 0
        while i < t.count {
            if t[i] == q[0] {
                var j = 1, k = i + 1
                while j < q.count && k < t.count {
                    if t[k] == q[j] { j += 1 }
                    k += 1
                }
                guard j == q.count else { break }
                if best == nil || k - i < best!.end - best!.start { best = (i, k) }
            }
            i += 1
        }
        guard let best else { return nil }
        let density = Double(q.count) / Double(best.end - best.start)
        guard density >= 0.33 else { return nil }
        var ranges: [Range<Int>] = []
        var j = 0
        for k in best.start..<best.end where j < q.count && t[k] == q[j] {
            ranges.append(k..<k + 1)
            j += 1
        }
        return (ranges, density)
    }

    /// Plages triees, contigues fusionnees.
    static func merge(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for r in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, r.lowerBound <= last.upperBound {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                out.append(r)
            }
        }
        return out
    }
}
