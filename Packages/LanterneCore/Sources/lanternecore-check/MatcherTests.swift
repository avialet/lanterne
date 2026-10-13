import Foundation
import LanterneCore

private func tier(_ query: String, _ title: String) -> MatchTier? {
    Matcher.match(SearchQuery(query), SearchText(title))?.tier
}

let matcherTests: (String, [Test]) = ("Matcher", [
    Test("normalizesCaseAndAccents") {
        let text = SearchText("R\u{00E9}glages Syst\u{00E8}me")
        expectEqual(text.normalized, "reglages systeme")
        expectEqual(SearchQuery("  R\u{00C9}G  ").normalized, "reg")
    },
    Test("exactBeatsPrefixBeatsWordStart") {
        expectEqual(tier("notes", "Notes"), .exact)
        expectEqual(tier("not", "Notes"), .prefix)
        expectEqual(tier("sys", "R\u{00E9}glages Syst\u{00E8}me"), .wordStart)
        expectEqual(tier("time", "FaceTime"), .wordStart, "camelCase")
        expectEqual(tier("rs", "R\u{00E9}glages Syst\u{00E8}me"), .acronym)
        expectEqual(tier("vsc", "Visual Studio Code"), .acronym)
        expectEqual(tier("ote", "Notes"), .substring)
        expectEqual(tier("nts", "Notes"), .subsequence)
        expect(tier("xyz", "Notes") == nil)
    },
    Test("scoresFollowTiers") {
        let q = SearchQuery("cal")
        let prefix = Matcher.match(q, SearchText("Calendrier"))!.score
        let word = Matcher.match(q, SearchText("Mon calendrier"))!.score
        let sub = Matcher.match(q, SearchText("Musical"))!.score
        expect(prefix > word && word > sub, "\(prefix) \(word) \(sub)")
    },
    Test("shorterTitleWinsWithinTier") {
        let q = SearchQuery("note")
        expect(Matcher.match(q, SearchText("Notes"))!.score > Matcher.match(q, SearchText("Notes de r\u{00E9}union"))!.score)
    },
    Test("singleLetterOnlyMatchesStarts") {
        expectEqual(tier("n", "Notes"), .prefix)
        expectEqual(tier("s", "R\u{00E9}glages Syst\u{00E8}me"), .wordStart)
        expect(tier("o", "Notes") == nil, "pas de sous-chaine a une lettre")
    },
    Test("subsequenceMustBeDense") {
        expect(tier("ac", "a bxdefghijklmnopqrstuvwxyz long title c") == nil)
        expectEqual(tier("clt", "Calculette"), .subsequence)
    },
    Test("multiWordQueryMatchesTokens") {
        expectEqual(tier("reglages sys", "R\u{00E9}glages Syst\u{00E8}me"), .prefix)
        expectEqual(tier("sys reg", "R\u{00E9}glages Syst\u{00E8}me"), .tokens)
        expect(tier("sys zzz", "R\u{00E9}glages Syst\u{00E8}me") == nil)
    },
    Test("rangesPointAtOriginalCharacters") {
        let m = Matcher.match(SearchQuery("sys"), SearchText("R\u{00E9}glages Syst\u{00E8}me"))!
        expectEqual(m.ranges, [9..<12])
        let a = Matcher.match(SearchQuery("rs"), SearchText("R\u{00E9}glages Syst\u{00E8}me"))!
        expectEqual(a.ranges, [0..<1, 9..<10])
        let s = Matcher.match(SearchQuery("clt"), SearchText("Calculette"))!
        expectEqual(s.ranges.count, 3)
    },
    Test("rangesSurviveLigaturesAndCombiningMarks") {
        // e + accent combinant : un seul caractere affiche.
        let m = Matcher.match(SearchQuery("ete"), SearchText("E\u{0301}te\u{0301} 2026"))!
        expectEqual(m.ranges, [0..<3])
    },
    Test("keywordsMatchOnlyAtWordStarts") {
        let text = SearchText("Clavier", keywords: ["Keyboard", "dict\u{00E9}e vocale"])
        let m = Matcher.match(SearchQuery("keyb"), text)!
        expectEqual(m.tier, .keyword)
        expect(m.ranges.isEmpty)
        expectEqual(m.keyword, "Keyboard", "mot-cle trouve, pour l'afficher")
        expect(Matcher.match(SearchQuery("cla"), text)?.keyword == nil)
        expectEqual(Matcher.match(SearchQuery("voc"), text)?.tier, .keyword)
        expect(Matcher.match(SearchQuery("eyb"), text) == nil)
        expect(Matcher.match(SearchQuery("k"), text) == nil, "une lettre : pas de mot-cle")
    },
    Test("titleBeatsKeyword") {
        let text = SearchText("Calculette", keywords: ["Calculator"])
        expectEqual(Matcher.match(SearchQuery("calcul"), text)?.tier, .prefix)
    },
    Test("letterMaskRejectsQuickly") {
        let text = SearchText("Notes")
        expect(!text.mayContain(SearchQuery("xz")))
        expect(text.mayContain(SearchQuery("nts")))
    },
])
