import Foundation
import GRDB

/// Ouvertures et elements oublies, dans la base de l'app. Purge au-dela de la duree de memoire et d'un
/// plafond de lignes ; « Oublier » supprime les ouvertures d'un element et l'exclut de l'apprentissage.
public final class HabitStore: Sendable {
    public static let maxRows = 20_000
    public let database: AppDatabase

    public init(_ database: AppDatabase) { self.database = database }

    /// Enregistre une ouverture ; false (rien d'ecrit) si l'element a ete oublie.
    @discardableResult
    public func record(_ opening: Opening) throws -> Bool {
        try database.write { db in
            if try Bool.fetchOne(db, sql: "SELECT 1 FROM forgotten WHERE itemKey = ?", arguments: [opening.itemKey]) == true {
                return false
            }
            try db.execute(sql: """
                INSERT INTO openings (itemKey, title, kind, openedAt, hour, weekday, contextApp, prefix)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [opening.itemKey, opening.title, opening.kind.rawValue, opening.openedAt, opening.hour,
                                 opening.weekday, opening.contextApp, opening.prefix])
            return true
        }
    }

    /// Ouvertures, de la plus ancienne a la plus recente.
    public func openings(since: Date? = nil) throws -> [Opening] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM openings WHERE openedAt >= ? ORDER BY openedAt, id
                """, arguments: [since ?? Date.distantPast])
            return rows.map { row in
                Opening(id: row["id"], itemKey: row["itemKey"], title: row["title"],
                        kind: ItemKind(rawValue: row["kind"]) ?? .file, openedAt: row["openedAt"], hour: row["hour"],
                        weekday: row["weekday"], contextApp: row["contextApp"], prefix: row["prefix"])
            }
        }
    }

    public func count() throws -> Int {
        try database.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM openings") ?? 0 }
    }

    /// Supprime ce que Lanterne a appris de cet element et ne l'apprend plus.
    public func forget(_ itemKey: String) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM openings WHERE itemKey = ?", arguments: [itemKey])
            try db.execute(sql: "INSERT OR IGNORE INTO forgotten (itemKey) VALUES (?)", arguments: [itemKey])
        }
    }

    public func unforget(_ itemKey: String) throws {
        try database.write { db in try db.execute(sql: "DELETE FROM forgotten WHERE itemKey = ?", arguments: [itemKey]) }
    }

    public func forgotten() throws -> Set<String> {
        try database.read { db in Set(try String.fetchAll(db, sql: "SELECT itemKey FROM forgotten")) }
    }

    /// Tout ce que Lanterne a appris, et la liste des oublis.
    public func eraseAll() throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM openings")
            try db.execute(sql: "DELETE FROM forgotten")
        }
    }

    /// Retire les ouvertures de plus de `keepDays` jours, puis les plus anciennes au-dela de `maxRows`.
    public func purge(now: Date = Date(), keepDays: Int = 365, maxRows: Int = HabitStore.maxRows) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM openings WHERE openedAt < ?",
                           arguments: [now.addingTimeInterval(-Double(keepDays) * 86400)])
            try db.execute(sql: """
                DELETE FROM openings WHERE id NOT IN (SELECT id FROM openings ORDER BY openedAt DESC, id DESC LIMIT ?)
                """, arguments: [maxRows])
        }
    }
}
