import Foundation
import GRDB

/// Schema de la base. Une migration par version du schema, jamais modifiee
/// une fois publiee : on en ajoute une nouvelle (`v2`, `v3`...).
enum Migrations {
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        #if DEBUG
        m.eraseDatabaseOnSchemaChange = true
        #endif

        m.registerMigration("v1") { db in
            try db.create(table: "meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            // Une ligne par ouverture : quoi, quand, depuis quelle app, apres quelles lettres.
            try db.create(table: "openings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("itemKey", .text).notNull().indexed()
                t.column("title", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("openedAt", .datetime).notNull().indexed()
                t.column("hour", .integer).notNull()
                t.column("weekday", .integer).notNull()
                t.column("contextApp", .text)
                t.column("prefix", .text).notNull().defaults(to: "")
            }
            // Elements oublies : plus appris, plus suggeres.
            try db.create(table: "forgotten") { t in
                t.primaryKey("itemKey", .text)
            }
        }

        return m
    }
}
