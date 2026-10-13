import Foundation
import LanterneCore

let habitStoreTests: (String, [Test]) = ("HabitStore", [
    Test("recordAndReadBack") {
        let store = HabitStore(try AppDatabase.inMemory())
        expect(try store.record(opening("app:a", daysAgo: 1, hour: 8, context: "m", prefix: "sa", title: "A")))
        try store.record(opening("app:b", daysAgo: 0))
        let all = try store.openings()
        expectEqual(all.count, 2)
        expectEqual(all.first?.itemKey, "app:a", "du plus ancien au plus recent")
        expectEqual(all.first?.prefix, "sa")
        expectEqual(all.first?.contextApp, "m")
        expectEqual(all.first?.hour, 8)
        expect(all.first?.id != nil)
        expectEqual(try store.openings(since: habitNow.addingTimeInterval(-3600)).map(\.itemKey), ["app:b"])
        expectEqual(try store.count(), 2)
    },
    Test("forgetDeletesAndExcludes") {
        let store = HabitStore(try AppDatabase.inMemory())
        try store.record(opening("file:/x"))
        try store.record(opening("file:/x", daysAgo: 1))
        try store.record(opening("app:b"))
        try store.forget("file:/x")
        expectEqual(try store.openings().map(\.itemKey), ["app:b"])
        expectEqual(try store.forgotten(), ["file:/x"])
        expect(try !store.record(opening("file:/x")), "un element oublie n'est plus appris")
        try store.unforget("file:/x")
        expect(try store.record(opening("file:/x")))
    },
    Test("purgeOldRowsAndCap") {
        let store = HabitStore(try AppDatabase.inMemory())
        for day in [400.0, 300, 2, 1, 0] { try store.record(opening("app:a", daysAgo: day)) }
        try store.purge(now: habitNow, keepDays: 365, maxRows: 2)
        let left = try store.openings()
        expectEqual(left.count, 2)
        expect(left.allSatisfy { habitNow.timeIntervalSince($0.openedAt) < 1.5 * 86400 }, "les plus recentes")
    },
    Test("eraseAll") {
        let store = HabitStore(try AppDatabase.inMemory())
        try store.record(opening("app:a"))
        try store.forget("app:b")
        try store.eraseAll()
        expectEqual(try store.count(), 0)
        expectEqual(try store.forgotten(), [])
    },
    Test("forgetLeavesNoTraceOnDisk") {
        try withTemporaryStore { store, files in
            try store.record(opening("file:/tmp/a", title: "titre-secret-oubli", kind: .file))
            try store.record(opening("app:garde", title: "titre-garde"))
            expect(files().contains { $0.contains("titre-secret-oubli") }, "temoin : la chaine est bien ecrite")
            try store.forget("file:/tmp/a")
            expect(!files().contains { $0.contains("titre-secret-oubli") }, "oubli : plus rien dans .sqlite ni -wal")
            expectEqual(try store.count(), 1)
        }
    },
    Test("eraseAndPurgeLeaveNoTraceOnDisk") {
        try withTemporaryStore { store, files in
            try store.record(opening("app:vieux", daysAgo: 400, title: "titre-secret-purge"))
            try store.record(opening("app:b", title: "titre-secret-efface"))
            try store.purge(now: habitNow, keepDays: 365)
            expect(!files().contains { $0.contains("titre-secret-purge") }, "purge")
            try store.eraseAll()
            expect(!files().contains { $0.contains("titre-secret-efface") }, "tout effacer")
        }
    },
])

/// Base sur disque jetable ; `files()` lit `.sqlite` et `-wal` (octets en Latin-1, pour chercher une chaine ASCII).
func withTemporaryStore(_ body: (HabitStore, () -> [String]) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lanterne-check-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("lanterne.sqlite")
    let store = HabitStore(try AppDatabase.open(at: url))
    let files: () -> [String] = {
        [url.path, url.path + "-wal"].compactMap { FileManager.default.contents(atPath: $0) }
            .map { String(decoding: $0.map { $0 == 0 ? 32 : $0 }, as: UTF8.self) }
    }
    try body(store, files)
}
