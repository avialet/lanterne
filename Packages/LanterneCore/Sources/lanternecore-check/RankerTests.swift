import Foundation
import LanterneCore

private func app(_ name: String, lastUsedDaysAgo: Double? = nil) -> Item {
    Item(key: Item.appKey("test." + name), title: name, kind: .app, target: "/Applications/\(name).app",
         lastUsed: lastUsedDaysAgo.map { habitNow.addingTimeInterval(-$0 * 86400) })
}

private func file(_ path: String, lastUsedDaysAgo: Double? = nil) -> Item {
    Item(key: Item.fileKey(path), title: (path as NSString).lastPathComponent, kind: .file, target: path,
         lastUsed: lastUsedDaysAgo.map { habitNow.addingTimeInterval(-$0 * 86400) })
}

private func context(hour: Int, app: String? = nil) -> SearchContext {
    SearchContext(now: habitNow, hour: hour, contextApp: app)
}

private let none = HabitModel(openings: [], now: habitNow)

private func titles(_ sections: [ResultSection]) -> [String] {
    sections.flatMap { $0.items.map(\.item.title) }
}

let rankerTests: (String, [Test]) = ("Ranker", [
    Test("bestFirstThenSectionsInFixedOrder") {
        let setting = Item(key: Item.settingKey("k"), title: "Calcul du clavier", kind: .setting, target: "x-apple.systempreferences:k")
        let index = SearchIndex(items: [app("Calendrier"), app("Calculette"), file("/tmp/Notes de calcul.txt"), setting])
        let result = index.search(SearchQuery("calc"), habits: none, context: context(hour: 9), exclusions: Exclusions())
        expectEqual(result.map(\.kind), [.best, .settings, .files])
        expectEqual(result.first?.items.first?.item.title, "Calculette")
        expect(result.first?.items.first?.match?.tier == .prefix)
    },
    Test("habitsLiftAmongEqualMatches") {
        let items = [app("Safari"), app("Saisie")]
        let index = SearchIndex(items: items)
        let cold = index.search(SearchQuery("sa"), habits: none, context: context(hour: 9), exclusions: Exclusions())
        expectEqual(titles(cold), ["Safari", "Saisie"])
        let habits = HabitModel(openings: (0..<3).map { opening(items[1].key, daysAgo: Double($0), prefix: "sa") }, now: habitNow)
        let warm = index.search(SearchQuery("sa"), habits: habits, context: context(hour: 9), exclusions: Exclusions())
        expectEqual(titles(warm), ["Saisie", "Safari"])
    },
    Test("learningNeverShowsUnrelatedItems") {
        let items = [app("Musique"), app("Notes")]
        let habits = HabitModel(openings: (0..<40).map { opening(items[0].key, daysAgo: Double($0) / 4, prefix: "no") }, now: habitNow)
        let result = SearchIndex(items: items).search(SearchQuery("no"), habits: habits, context: context(hour: 9), exclusions: Exclusions())
        expectEqual(titles(result), ["Notes"])
    },
    Test("frequencyCannotCarryWeakMatch") {
        let weak = file("/tmp/Nouvelle t\u{00EA}te.txt")
        let habits = HabitModel(openings: (0..<50).map { opening(weak.key, daysAgo: Double($0) / 5, kind: .file) }, now: habitNow)
        let result = SearchIndex(items: [weak, app("Notes")])
            .search(SearchQuery("note"), habits: habits, context: context(hour: 9), exclusions: Exclusions())
        expectEqual(titles(result).first, "Notes")
        expectEqual(titles(result).count, 2)
    },
    Test("spotlightPriorBreaksColdTies") {
        let index = SearchIndex(items: [file("/tmp/rapport-a.pdf", lastUsedDaysAgo: 90), file("/tmp/rapport-b.pdf", lastUsedDaysAgo: 1)])
        let result = index.search(SearchQuery("rapport"), habits: none, context: context(hour: 9), exclusions: Exclusions())
        expectEqual(titles(result), ["rapport-b.pdf", "rapport-a.pdf"])
    },
    Test("stableOrderOnTies") {
        let index = SearchIndex(items: [app("Beta"), app("Bravo"), app("Bingo"), app("Bingo")])
        let a = titles(index.search(SearchQuery("b"), habits: none, context: context(hour: 9), exclusions: Exclusions()))
        expectEqual(a, ["Beta", "Bingo", "Bravo"], "doublons de cle retires, departage par longueur puis titre")
        expectEqual(index.count, 3)
    },
    Test("exclusionsHideFilesAndForgottenItems") {
        let home = "/Users/demo"
        var exclusions = Exclusions(folders: Exclusions.defaultFolders(home: home), extensions: ["log"])
        expect(exclusions.excludes(path: "/Users/demo/code/node_modules/x/readme.md"))
        expect(exclusions.excludes(path: "/Users/demo/.config/a.txt"))
        expect(exclusions.excludes(path: "/Users/demo/Library/Caches/a.txt"))
        expect(exclusions.excludes(path: "/Users/demo/Documents/trace.LOG"))
        expect(!exclusions.excludes(path: "/Users/demo/Documents/Library notes.txt"))
        expect(!exclusions.excludes(path: "/Users/demo/Documents/a.txt"))
        let doc = file("/Users/demo/Documents/a.txt")
        let notes = app("Notes")
        exclusions.forgotten = [doc.key, notes.key]
        let index = SearchIndex(items: [doc, notes, file("/Users/demo/Library/a.txt")])
        expectEqual(titles(index.search(SearchQuery("a"), habits: none, context: context(hour: 9), exclusions: exclusions)), [])
        expectEqual(titles(index.search(SearchQuery("not"), habits: none, context: context(hour: 9), exclusions: exclusions)), ["Notes"],
                    "une app oubliee reste trouvable")
    },
    Test("suggestionsFollowHourAndContext") {
        let mail = app("Mail"), music = app("Musique"), maps = app("Plans", lastUsedDaysAgo: 2)
        let openings = (0..<8).map { opening(mail.key, daysAgo: Double($0), hour: 9, context: "com.apple.Safari") }
            + (0..<8).map { opening(music.key, daysAgo: Double($0), hour: 21) }
        let habits = HabitModel(openings: openings, now: habitNow)
        let index = SearchIndex(items: [mail, music, maps, app("Jamais")])
        let morning = index.suggestions(habits: habits, context: context(hour: 9), exclusions: Exclusions(), limit: 8) { _ in nil }
        expectEqual(morning.map(\.item.title), ["Mail", "Musique", "Plans"], "a froid : apps recentes ensuite")
        let evening = index.suggestions(habits: habits, context: context(hour: 21), exclusions: Exclusions(), limit: 2) { _ in nil }
        expectEqual(evening.map(\.item.title), ["Musique", "Mail"])
    },
    Test("suggestionsUseOrphansAndSkipForgotten") {
        let gone = opening(Item.fileKey("/tmp/orphelin.txt"), title: "orphelin.txt", kind: .file)
        let mail = app("Mail")
        let habits = HabitModel(openings: [gone, opening(mail.key)], now: habitNow)
        let index = SearchIndex(items: [mail])
        var exclusions = Exclusions()
        let all = index.suggestions(habits: habits, context: context(hour: 9), exclusions: exclusions, limit: 8) { profile in
            Item.path(fromKey: profile.key).map { Item(key: profile.key, title: profile.title, kind: profile.kind, target: $0) }
        }
        expectEqual(Set(all.map(\.item.title)), ["orphelin.txt", "Mail"])
        exclusions.forgotten = [mail.key]
        let rest = index.suggestions(habits: habits, context: context(hour: 9), exclusions: exclusions, limit: 8) { _ in nil }
        expectEqual(rest.map(\.item.title), [])
    },
    Test("furtherDedupesExcludesAndLimits") {
        let index = SearchIndex(items: [file("/tmp/budget.xlsx")])
        let found = [file("/tmp/budget.xlsx"), file("/tmp/budget 2025.xlsx", lastUsedDaysAgo: 3),
                     file("/tmp/node_modules/budget.js"), file("/tmp/vieux budget.xlsx", lastUsedDaysAgo: 30),
                     file("/tmp/budget final.xlsx")]
        let section = index.further(found, query: SearchQuery("budget"), shown: [], exclusions: Exclusions(), limit: 2)
        expectEqual(section?.kind, .further)
        expectEqual(section?.items.map(\.item.title), ["budget 2025.xlsx", "budget final.xlsx"])
        expect(index.further([file("/tmp/budget.xlsx")], query: SearchQuery("budget"), shown: [], exclusions: Exclusions(), limit: 5) == nil)
    },
    Test("contextComputesLocalHour") {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 22))!
        expectEqual(SearchContext(now: date, contextApp: nil, calendar: calendar).hour, 22)
    },
])
