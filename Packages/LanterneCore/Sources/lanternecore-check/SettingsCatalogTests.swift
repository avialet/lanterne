import Foundation
import LanterneCore

private func settingsInfo(_ id: String, display: String, url: Bool = true,
                          point: String = "com.apple.Settings.extension.ui", terms: String? = "Keyboard") -> [String: Any] {
    var attributes: [String: Any] = ["allowsXAppleSystemPreferencesURLScheme": url]
    if let terms { attributes["searchTermsFileName"] = terms }
    return ["CFBundleIdentifier": id, "CFBundleDisplayName": display,
            "EXAppExtensionAttributes": ["EXExtensionPointIdentifier": point, "SettingsExtensionAttributes": attributes]]
}

private func keyboardTerms() -> [String: Any] { [
    "Dictation": ["localizableStrings": [["index": "dicter, dict\u{00E9}e, micro", "title": "Dict\u{00E9}e"]]],
    "CapsLock": ["localizableStrings": [["index": "verr maj, micro", "title": "Verrouillage"], ["title": "Dict\u{00E9}e"]]],
] }

let settingsCatalogTests: (String, [Test]) = ("SettingsCatalog", [
    Test("readsFrenchNameAndSearchTerms") {
        let item = SettingsCatalog.item(info: settingsInfo("com.apple.Keyboard-Settings.extension", display: "Keyboard"),
                                        localizedNames: ["fr": ["CFBundleDisplayName": "Clavier"]],
                                        searchTerms: keyboardTerms())
        expectEqual(item?.title, "Clavier")
        expectEqual(item?.key, "setting:com.apple.Keyboard-Settings.extension")
        expectEqual(item?.target, "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        expectEqual(item?.kind, .setting)
        expectEqual(item?.subtitle, "R\u{00E9}glages Syst\u{00E8}me")
        let keywords = item?.keywords ?? []
        expect(keywords.contains("Keyboard"), "nom anglais")
        expect(keywords.contains("Dict\u{00E9}e") && keywords.contains("verr maj") && keywords.contains("micro"))
        expectEqual(keywords.filter { $0 == "micro" }.count, 1, "sans doublon")
        expectEqual(keywords.filter { $0 == "Dict\u{00E9}e" }.count, 1, "sans doublon")
    },
    Test("ignoresOtherExtensionsAndClosedPanels") {
        expect(SettingsCatalog.item(info: settingsInfo("a", display: "A", point: "com.apple.widgetkit"), localizedNames: nil, searchTerms: nil) == nil)
        expect(SettingsCatalog.item(info: settingsInfo("a", display: "Maison", url: false), localizedNames: nil, searchTerms: nil) == nil)
        expect(SettingsCatalog.item(info: [:], localizedNames: nil, searchTerms: nil) == nil)
    },
    Test("technicalNamesFallBackOrAreDropped") {
        let battery = SettingsCatalog.item(info: settingsInfo("com.apple.Battery-Settings.extension", display: "PowerPreferences"),
                                           localizedNames: ["fr": ["NSHumanReadableCopyright": "x"]], searchTerms: nil)
        expectEqual(battery?.title, "Batterie")
        let headphones = SettingsCatalog.item(info: settingsInfo("com.apple.HeadphoneSettings", display: "HeadphoneSettingsExtension"),
                                              localizedNames: ["fr": ["CFBundleDisplayName": "HeadphoneSettingsExtension"]], searchTerms: nil)
        expect(headphones == nil)
        let followUps = SettingsCatalog.item(info: settingsInfo("com.apple.FollowUp", display: "FollowUps"),
                                             localizedNames: ["fr": ["CFBundleDisplayName": "FollowUps"]], searchTerms: nil)
        expect(followUps == nil)
        let wifi = SettingsCatalog.item(info: settingsInfo("com.apple.wifi-settings-extension", display: "Wi-Fi"),
                                        localizedNames: ["fr": ["CFBundleDisplayName": "Wi\u{2011}Fi"]], searchTerms: nil)
        expectEqual(wifi?.title, "Wi\u{2011}Fi")
        expect(!SettingsCatalog.isTechnicalName("iCloud"))
        expect(SettingsCatalog.isTechnicalName("FollowUps"))
    },
    Test("frozenListWhenCatalogIsUnreadable") {
        let fallback = SettingsCatalog.catalog(found: [])
        expect(fallback.count >= 30, "\(fallback.count)")
        expectEqual(Set(fallback.map(\.title)).count, fallback.count)
        expect(fallback.allSatisfy { $0.key.hasPrefix("setting:") && $0.target.hasPrefix("x-apple.systempreferences:") })
        let found = (0..<12).map { Item(key: Item.settingKey("p\($0)"), title: "P\($0)", kind: .setting, target: "x") }
        expectEqual(SettingsCatalog.catalog(found: found).count, 12)
    },
])
