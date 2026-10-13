import Foundation
import LanterneCore

private let control: UInt = 1 << 18
private let command: UInt = 1 << 20

let symbolicHotKeysTests: (String, [Test]) = ("SymbolicHotKeys", [
    Test("defaultsWhenAbsent") {
        let table = SymbolicHotKeys.parse(nil)
        expectEqual(table[60]?.enabled, true)
        expectEqual(table[64]?.enabled, true)
        expectEqual(SymbolicHotKeys.conflict(keyCode: 49, modifiers: control, in: table)?.id, 60)
        expectEqual(SymbolicHotKeys.conflict(keyCode: 49, modifiers: command, in: table)?.id, 64)
        expect(SymbolicHotKeys.conflict(keyCode: 49, modifiers: control | (1 << 17), in: table) == nil)
    },
    Test("readsPreferences") {
        let prefs: [String: Any] = [
            "60": ["enabled": NSNumber(value: 0), "value": ["parameters": [32, 49, 262144], "type": "standard"]],
            "64": ["enabled": true, "value": ["parameters": [65535, 49, 1048576], "type": "standard"]],
            "999": ["enabled": 1],
        ]
        let table = SymbolicHotKeys.parse(prefs)
        expectEqual(table[60]?.enabled, false)
        expect(SymbolicHotKeys.conflict(keyCode: 49, modifiers: control, in: table) == nil, "60 desactive : Ctrl-Espace libre")
        expectEqual(SymbolicHotKeys.conflict(keyCode: 49, modifiers: command, in: table)?.title, "Afficher la recherche Spotlight")
        expect(SymbolicHotKeys.isSpotlightEnabled(table))
        let off = SymbolicHotKeys.parse(["64": ["enabled": false]])
        expect(!SymbolicHotKeys.isSpotlightEnabled(off))
        expect(SymbolicHotKeys.conflict(keyCode: 49, modifiers: command, in: off) == nil)
    },
    Test("ignoresOtherModifierBits") {
        let table = SymbolicHotKeys.parse(nil)
        expectEqual(SymbolicHotKeys.conflict(keyCode: 49, modifiers: control | 0x100, in: table)?.id, 60)
    },
])
