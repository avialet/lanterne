import Foundation
import LanterneCore

let vialetActionLinkTests: (String, [Test]) = ("VialetActionLink", [
    Test("buildsTheAppOwnScheme") {
        expectEqual(VialetActionLink.url(bundleIdentifier: "fr.vialet.chuchote", scheme: "chuchote", actionId: "dicter")?.absoluteString,
                    "chuchote://dicter")
        expectEqual(VialetActionLink.url(bundleIdentifier: "fr.vialet.pico", scheme: "pico", actionId: "new-task-2")?.absoluteString,
                    "pico://new-task-2")
    },
    Test("rejectsForeignSchemesAndBundles") {
        expect(VialetActionLink.url(bundleIdentifier: "fr.vialet.chuchote", scheme: "https", actionId: "dicter") == nil)
        expect(VialetActionLink.url(bundleIdentifier: "fr.vialet.chuchote", scheme: "pico", actionId: "dicter") == nil)
        expect(VialetActionLink.url(bundleIdentifier: "com.exemple.chuchote", scheme: "chuchote", actionId: "dicter") == nil)
        expect(VialetActionLink.url(bundleIdentifier: "fr.vialet.Chu-chote", scheme: "chu-chote", actionId: "dicter") == nil)
        expect(VialetActionLink.url(bundleIdentifier: "fr.vialet.", scheme: "", actionId: "dicter") == nil)
    },
    Test("rejectsInvalidActionIdentifiers") {
        for id in ["", "Dicter", "a/b", "a b", "../x", "x?y=1", "update", "open", String(repeating: "a", count: 41), "-x", "d\u{00E9}"] {
            expect(VialetActionLink.url(bundleIdentifier: "fr.vialet.chuchote", scheme: "chuchote", actionId: id) == nil, id)
        }
        expect(VialetActionLink.url(bundleIdentifier: "fr.vialet.chuchote", scheme: "chuchote",
                                    actionId: String(repeating: "a", count: 40)) != nil)
    },
])
