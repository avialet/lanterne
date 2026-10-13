import Foundation
import LanterneCore

let habitNow = Date(timeIntervalSince1970: 1_790_000_000)

func opening(_ key: String, daysAgo: Double = 0, hour: Int = 9, context: String? = nil, prefix: String = "",
             title: String = "Element", kind: ItemKind = .app) -> Opening {
    Opening(itemKey: key, title: title, kind: kind, openedAt: habitNow.addingTimeInterval(-daysAgo * 86400),
            hour: hour, weekday: 2, contextApp: context, prefix: prefix)
}

let habitsTests: (String, [Test]) = ("Habits", [
    Test("itemKeys") {
        expectEqual(Item.appKey("com.apple.Notes"), "app:com.apple.Notes")
        expectEqual(Item.fileKey("/tmp/a b.txt"), "file:/tmp/a b.txt")
        expectEqual(Item.settingKey("com.apple.Keyboard-Settings.extension"), "setting:com.apple.Keyboard-Settings.extension")
        expectEqual(Item.actionKey(bundle: "fr.vialet.chuchote", id: "dicter"), "action:fr.vialet.chuchote#dicter")
        expectEqual(Item.path(fromKey: "file:/tmp/a b.txt"), "/tmp/a b.txt")
        expect(Item.path(fromKey: "app:x") == nil)
    },
    Test("openingRecordsHourAndShortPrefix") {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9, minute: 30))!
        let item = Item(key: Item.appKey("com.apple.Safari"), title: "Safari", kind: .app, target: "/Applications/Safari.app")
        let o = Opening(item: item, at: date, contextApp: "com.apple.mail", query: "  SAF\u{00C9}  tres longue requete", calendar: calendar)
        expectEqual(o.hour, 9)
        expectEqual(o.weekday, 4)
        expectEqual(o.prefix, "safe tres lo")
        expectEqual(o.prefix.count, 12)
        expectEqual(o.contextApp, "com.apple.mail")
    },
    Test("decayHalvesAfterHalfLife") {
        let model = HabitModel(openings: [opening("a", daysAgo: 14)], now: habitNow)
        let d = model.profiles["a"]!.decayed
        expect(abs(d - 0.5) < 0.01, "\(d)")
    },
    Test("hourAffinityPrefersUsualHour") {
        let model = HabitModel(openings: (0..<10).map { opening("a", daysAgo: Double($0), hour: 9) }, now: habitNow)
        let p = model.profiles["a"]!
        expect(p.hourAffinity(9) > 3)
        expect(p.hourAffinity(8) > 1.5, "lissage a +-1 h")
        expect(p.hourAffinity(21) < 0.5)
        let empty = HabitModel(openings: [], now: habitNow)
        expect(empty.profiles["a"] == nil)
    },
    Test("boostGrowsSlowlyWithFrequency") {
        let few = HabitModel(openings: (0..<2).map { opening("a", daysAgo: Double($0)) }, now: habitNow)
        let many = HabitModel(openings: (0..<20).map { opening("a", daysAgo: Double($0) / 4) }, now: habitNow)
        let q = SearchQuery("")
        let b2 = few.boost(key: "a", query: q, hour: 9, contextApp: nil).total
        let b20 = many.boost(key: "a", query: q, hour: 9, contextApp: nil).total
        expect(b20 > b2, "\(b20) \(b2)")
        expect(b20 < 3 * b2, "amorti : \(b20) \(b2)")
        expectEqual(few.boost(key: "absent", query: q, hour: 9, contextApp: nil).total, 0)
    },
    Test("recentBeatsOld") {
        let model = HabitModel(openings: (0..<5).map { opening("recent", daysAgo: Double($0)) }
                               + (0..<5).map { opening("old", daysAgo: 60 + Double($0)) }, now: habitNow)
        let q = SearchQuery("")
        expect(model.boost(key: "recent", query: q, hour: 9, contextApp: nil).total
               > model.boost(key: "old", query: q, hour: 9, contextApp: nil).total)
    },
    Test("hourAndContextRaiseBoost") {
        let model = HabitModel(openings: (0..<6).map { opening("a", daysAgo: Double($0), hour: 9, context: "com.apple.mail") },
                               now: habitNow)
        let q = SearchQuery("")
        let morning = model.boost(key: "a", query: q, hour: 9, contextApp: nil).total
        let evening = model.boost(key: "a", query: q, hour: 20, contextApp: nil).total
        let fromMail = model.boost(key: "a", query: q, hour: 9, contextApp: "com.apple.mail").total
        expect(morning > evening)
        expect(fromMail > morning)
    },
    Test("typedPrefixIsTheStrongSignal") {
        let model = HabitModel(openings: (0..<4).map { opening("a", daysAgo: Double($0), prefix: "sa") }, now: habitNow)
        let same = model.boost(key: "a", query: SearchQuery("sa"), hour: 3, contextApp: nil).prefix
        let shorter = model.boost(key: "a", query: SearchQuery("s"), hour: 3, contextApp: nil).prefix
        let longer = model.boost(key: "a", query: SearchQuery("saf"), hour: 3, contextApp: nil).prefix
        let other = model.boost(key: "a", query: SearchQuery("x"), hour: 3, contextApp: nil).prefix
        expect(same > 1, "\(same)")
        expect(same > shorter && shorter > 0)
        expect(same > longer && longer > 0)
        expectEqual(other, 0)
        expectEqual(model.prefixCount(key: "a", query: SearchQuery("SA")), 4)
    },
    Test("explainCountHourAndContext") {
        let model = HabitModel(openings: (0..<12).map { opening("a", daysAgo: Double($0) / 2, hour: 9, context: "com.apple.mail") },
                               now: habitNow)
        let text = model.explain(key: "a", now: habitNow) { $0 == "com.apple.mail" ? "Mail" : nil }
        expectEqual(text, "12 fois cette semaine, souvent vers 9 h depuis Mail")
    },
    Test("explainPeriod") {
        let hours = [8, 9, 10, 11, 8, 9, 10, 11]
        let model = HabitModel(openings: hours.enumerated().map { opening("a", daysAgo: Double($0.offset) / 2, hour: $0.element) },
                               now: habitNow)
        expectEqual(model.explain(key: "a", now: habitNow) { _ in nil }, "8 fois cette semaine, surtout le matin")
    },
    Test("explainSingleAndOld") {
        let one = HabitModel(openings: [opening("a", daysAgo: 1, hour: 15)], now: habitNow)
        expectEqual(one.explain(key: "a", now: habitNow) { _ in nil }, "Une fois cette semaine")
        let old = HabitModel(openings: [opening("a", daysAgo: 20), opening("a", daysAgo: 30), opening("a", daysAgo: 40, hour: 18)],
                             now: habitNow)
        expectEqual(old.explain(key: "a", now: habitNow) { _ in nil }, "3 fois, la derni\u{00E8}re il y a 20 jours, souvent vers 9 h")
        expect(old.explain(key: "absent", now: habitNow) { _ in nil } == nil)
    },
    Test("profileSummaryForHabitsWindow") {
        let model = HabitModel(openings: [opening("a", daysAgo: 1, hour: 9, context: "x", title: "Ancien"),
                                          opening("a", daysAgo: 0, hour: 10, context: "y", title: "Notes")], now: habitNow)
        let p = model.profiles["a"]!
        expectEqual(p.title, "Notes", "le titre le plus recent")
        expectEqual(p.count, 2)
        expectEqual(p.hourCounts[9], 1)
        expectEqual(p.hourCounts[10], 1)
        expectEqual(p.topContexts(limit: 3).count, 2)
        expectEqual(model.ordered.map(\.key), ["a"])
    },
])
