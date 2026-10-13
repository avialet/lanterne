import Foundation
import LanterneCore

/// Generateur deterministe (xorshift), pour un banc reproductible.
struct Seeded {
    var state: UInt64
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    mutating func pick<T>(_ list: [T]) -> T { list[Int(next() % UInt64(list.count))] }
}

private let syllables = ["ca", "la", "re", "no", "te", "ma", "pi", "so", "ver", "di", "lu", "ga", "tor", "mi", "be",
                         "\u{00E9}t\u{00E9}", "pro", "jet", "rap", "port", "fac", "ture", "plan", "ning", "bud", "get"]

private func word(_ rng: inout Seeded) -> String {
    (0..<(2 + Int(rng.next() % 3))).map { _ in rng.pick(syllables) }.joined()
}

/// 10 000 elements, 2 000 ouvertures, 200 requetes : temps par frappe (recherche et classement).
func benchmark() -> (p50: Double, p95: Double, build: Double) {
    var rng = Seeded(state: 0x9E37_79B9_7F4A_7C15)
    var items: [Item] = []
    for i in 0..<10_000 {
        let words = (0..<(1 + Int(rng.next() % 3))).map { _ in word(&rng) }
        let title = words.joined(separator: i % 3 == 0 ? " " : "-").capitalized + (i % 4 == 0 ? ".pdf" : "")
        let kind: ItemKind = i < 300 ? .app : (i < 360 ? .setting : .file)
        items.append(Item(key: "k\(i)", title: title, keywords: kind == .setting ? [word(&rng), word(&rng)] : [],
                          kind: kind, target: "/tmp/\(i)", lastUsed: habitNow.addingTimeInterval(-Double(rng.next() % 90) * 86400)))
    }
    let start = Date()
    let index = SearchIndex(items: items)
    let build = Date().timeIntervalSince(start) * 1000
    var openings: [Opening] = []
    for _ in 0..<2_000 {
        let item = items[Int(rng.next() % 500)]
        openings.append(opening(item.key, daysAgo: Double(rng.next() % 60), hour: Int(rng.next() % 24),
                                context: rng.pick(["a", "b", "c"]), prefix: String(item.title.lowercased().prefix(2))))
    }
    let habits = HabitModel(openings: openings, now: habitNow)
    var queries: [String] = []
    for i in 0..<200 {
        let title = items[Int(rng.next() % 10_000)].title.lowercased()
        queries.append(i % 4 == 3 ? rng.pick(["ca", "rpt", "pro jet", "bg", "t", "fac", "xq"]) : String(title.prefix(1 + i % 6)))
    }
    var times: [Double] = []
    let context = SearchContext(now: habitNow, hour: 9, contextApp: "a")
    for q in queries {
        let t0 = DispatchTime.now().uptimeNanoseconds
        _ = index.search(SearchQuery(q), habits: habits, context: context, exclusions: Exclusions())
        times.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
    }
    times.sort()
    return (times[times.count / 2], times[Int(Double(times.count) * 0.95)], build)
}

let benchTests: (String, [Test]) = ("Bench", [
    Test("perKeystrokeLatency") {
        let r = benchmark()
        #if DEBUG
        let limit = 50.0, mode = "debug"
        #else
        let limit = 10.0, mode = "release"
        #endif
        print(String(format: "banc (%@) : 10 000 elements, 200 requetes, mediane %.2f ms, p95 %.2f ms, index %.0f ms",
                     mode, r.p50, r.p95, r.build))
        expect(r.p95 < limit, "p95 \(r.p95) ms > \(limit) ms")
    },
])
