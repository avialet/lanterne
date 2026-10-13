#if DEBUG
import AppKit
import LanterneCore

/// Sonde de l'app empaquetee (DEBUG) : `open Lanterne.app --args -LanterneProbe <fichier> -LanterneDBPath <base jetable>`.
/// Mesure la latence par frappe sur l'index reel de ce Mac (apps, reglages, fichiers recents) et compte, par
/// dossier, ce que Spotlight renvoie a l'app pour Documents, Bureau et Telechargements (TCC). N'ecrit que
/// des nombres : aucun nom de fichier, aucune requete tapee par l'utilisateur.
extension AppDelegate {
    func runProbeIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-" + Brand.name + "Probe"), i + 1 < args.count else { return false }
        let output = URL(fileURLWithPath: args[i + 1])
        Task { @MainActor in
            let report = await Self.probe()
            try? report.write(to: output, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
        return true
    }

    static func probe() async -> String {
        var lines: [String] = ["Sonde Lanterne \(AppInfo.version) (\(Bundle.main.bundlePath))", "date : \(Date())"]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = ["Documents", "Desktop", "Downloads"]
        func tally(_ paths: [String]) -> String {
            var counts: [String: Int] = [:]
            for p in paths {
                let folder = folders.first { p.hasPrefix(home + "/" + $0 + "/") } ?? "autres"
                counts[folder, default: 0] += 1
            }
            return (folders + ["autres"]).map { "\($0) \(counts[$0] ?? 0)" }.joined(separator: ", ")
        }

        let t0 = Date()
        let apps = await Task.detached { AppIndex.scan() }.value
        let tApps = Date().timeIntervalSince(t0) * 1000
        let t1 = Date()
        let settings = await Task.detached { SettingsIndex.load() }.value
        let tSettings = Date().timeIntervalSince(t1) * 1000
        lines.append(String(format: "apps : %d (parcours %.0f ms) ; reglages : %d (lecture %.0f ms)", apps.count, tApps,
                            settings.items.count, tSettings))

        // Fichiers recents : premiere reponse de la requete vivante (20 s au plus).
        var recents: [Item]?
        let t2 = Date()
        let recent = RecentFiles { items in if recents == nil { recents = items } }
        recent.start()
        for _ in 0..<200 where recents == nil { try? await Task.sleep(for: .milliseconds(100)) }
        recent.stop()
        let found = recents ?? []
        lines.append(String(format: "fichiers recents (90 j) : %d en %.0f ms ; %@", found.count,
                            Date().timeIntervalSince(t2) * 1000, tally(found.map(\.target))))
        let exclusions = Exclusions(folders: Exclusions.defaultFolders(home: home))
        let kept = found.filter { !exclusions.excludes($0) }
        lines.append("apres exclusions (node_modules, caches, ~/Library) : \(kept.count) ; \(tally(kept.map(\.target)))")

        // Spotlight longue traine (NSMetadataQuery, 200 au plus, 2 s au plus) : requetes generiques.
        let spotlight = SpotlightSearch()
        for q in ["pdf", "doc", "a", "e"] {
            let t = Date()
            let items = await spotlight.run(q)
            lines.append(String(format: "spotlight \u{00AB} %@ \u{00BB} : %d en %.0f ms ; %@", q, items.count,
                                Date().timeIntervalSince(t) * 1000, tally(items.map(\.target))))
        }

        // Latence par frappe sur l'index reel.
        let all = apps + settings.items + kept
        let t3 = Date()
        let index = SearchIndex(items: all)
        lines.append(String(format: "index : %d elements, construit en %.0f ms", index.count, Date().timeIntervalSince(t3) * 1000))
        var rng = SystemRandomNumberGenerator()
        var queries = ["s", "sa", "saf", "no", "not", "cal", "cla", "re", "reg", "rs", "pdf", "doc", "term", "x", "zz", "mail", "mu"]
        let titles = all.map { $0.title.lowercased() }
        for n in 0..<283 {
            let t = titles[Int.random(in: 0..<titles.count, using: &rng)]
            queries.append(String(t.prefix(1 + n % 5)))
        }
        let habits = HabitModel(openings: (try? AppState.shared.store.openings()) ?? [], now: Date())
        let context = SearchContext(contextApp: nil)
        var times: [Double] = []
        for q in queries {
            let s = DispatchTime.now().uptimeNanoseconds
            _ = index.search(SearchQuery(q), habits: habits, context: context, exclusions: exclusions)
            times.append(Double(DispatchTime.now().uptimeNanoseconds - s) / 1_000_000)
        }
        times.sort()
        lines.append(String(format: "frappe (debug, %d requetes) : mediane %.2f ms, p95 %.2f ms, max %.2f ms", times.count,
                            times[times.count / 2], times[Int(Double(times.count) * 0.95)], times.last ?? 0))
        let s = DispatchTime.now().uptimeNanoseconds
        _ = index.suggestions(habits: habits, context: context, exclusions: exclusions) { _ in nil }
        lines.append(String(format: "champ vide (suggestions) : %.2f ms", Double(DispatchTime.now().uptimeNanoseconds - s) / 1_000_000))
        return lines.joined(separator: "\n") + "\n"
    }
}
#endif
