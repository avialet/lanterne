import Foundation
import LanterneCore

let generationTests: (String, [Test]) = ("Generation", [
    Test("onlyTheLatestBuildIsAccepted") {
        var generation = Generation()
        let first = generation.next()
        let second = generation.next()
        expect(!generation.accept(first), "un index ancien n'ecrase pas le plus recent")
        expect(generation.accept(second))
        expect(!generation.accept(second), "une seule fois")
    },
    Test("lateOldBuildAfterNewerOneIsRejected") {
        var generation = Generation()
        let old = generation.next()
        let new = generation.next()
        expect(generation.accept(new))
        expect(!generation.accept(old))
    },
])
