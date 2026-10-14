import AppKit
import SwiftUI
import LanterneCore

/// Reglages : les cartes standard du kit, puis Remplacer Spotlight, Sources, Apprentissage, Exclusions.
struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        // Le defilement commence sous un lisere fixe : sans lui, la capture (CALayer.render) de macOS 26
        // ne rend rien d'une ScrollView collee au bord de la barre de titre.
        VStack(spacing: 0) {
            Theme.paper.frame(height: 1)
            ScrollView {
            SettingsScreen(app: Brand.identity, hotKey: HotKeyController.shared, updater: Updater.shared,
                           menuBar: MenuBarPresence.shared, dock: DockPresence.shared,
                           hotKeyHint: "Depuis n'importe quelle app : ouvre le champ de recherche de Lanterne.",
                           updateNote: HubPresence.updateNote,
                           width: 500) {
                SpotlightCard()
                SourcesCard()
                LearningCard()
                ExclusionsCard()
            }
            }
        }
        .frame(width: 500, height: 720)
        .background(Theme.paper)
        .tint(Theme.accent)
        .onAppear { state.refreshConflicts() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshConflicts()
        }
    }
}

/// Passer a Cmd-Espace : desactiver d'abord le raccourci de Spotlight dans Clavier, puis le prendre.
struct SpotlightCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let hotKey = HotKeyController.shared
        let usesCommandSpace = hotKey.shortcut == ShortcutConflicts.commandSpace
        SettingsCard(icon: "command", color: Theme.accent, title: "Remplacer Spotlight") {
            if usesCommandSpace {
                Text(state.spotlightShortcutEnabled
                     ? "Lanterne a pris \u{2318}Espace, mais Spotlight le garde tant que son raccourci est actif."
                     : "Lanterne r\u{00E9}pond \u{00E0} \u{2318}Espace. Spotlight reste accessible depuis la barre des menus.")
                    .font(Theme.ui(12)).foregroundStyle(state.spotlightShortcutEnabled ? Theme.coral : Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if state.spotlightShortcutEnabled {
                        PillButton("Ouvrir Clavier", primary: true) { ShortcutConflicts.openKeyboardSettings() }
                    }
                    PillButton("Revenir \u{00E0} \(hotKey.defaultShortcut.display)") {
                        hotKey.shortcut = hotKey.defaultShortcut
                        state.refreshConflicts()
                    }
                }
            } else {
                Text("Pour ouvrir Lanterne avec \u{2318}Espace\u{00A0}:")
                    .font(Theme.ui(12.5, weight: .medium)).foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 4) {
                    step(1, "Dans R\u{00E9}glages Syst\u{00E8}me \u{203A} Clavier, cliquez \u{00AB}\u{00A0}Raccourcis clavier\u{2026}\u{00A0}\u{00BB}.")
                    step(2, "Dans Spotlight, d\u{00E9}cochez \u{00AB}\u{00A0}Afficher la recherche Spotlight\u{00A0}\u{00BB} (\u{2318}Espace).")
                    step(3, "Revenez ici et cliquez \u{00AB}\u{00A0}Prendre \u{2318}Espace\u{00A0}\u{00BB}.")
                }
                HStack(spacing: 8) {
                    PillButton("Ouvrir Clavier", primary: state.spotlightShortcutEnabled) { ShortcutConflicts.openKeyboardSettings() }
                    PillButton("Prendre \u{2318}Espace", primary: !state.spotlightShortcutEnabled) {
                        hotKey.shortcut = ShortcutConflicts.commandSpace
                        state.refreshConflicts()
                    }
                    .disabled(state.spotlightShortcutEnabled)
                    .opacity(state.spotlightShortcutEnabled ? 0.45 : 1)
                }
                Text(state.spotlightShortcutEnabled
                     ? "\u{2318}Espace est encore pris par Spotlight."
                     : "\u{2318}Espace est libre.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(n).").font(Theme.ui(12, weight: .bold)).foregroundStyle(Theme.accent)
            Text(text).font(Theme.ui(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SourcesCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        SettingsCard(icon: "tray.full", color: Theme.sea, title: "Sources") {
            Toggle("Apps", isOn: $state.useApps)
            Toggle("Panneaux des R\u{00E9}glages Syst\u{00E8}me", isOn: $state.useSettings)
            Toggle("Fichiers et dossiers r\u{00E9}cents (\(RecentFiles.days) jours)", isOn: $state.useRecents)
            Toggle("Plus loin\u{00A0}: recherche Spotlight par nom", isOn: $state.useSpotlight)
            Toggle("Actions des apps vialet.app", isOn: $state.useActions)
            Text("Index en m\u{00E9}moire\u{00A0}: \(state.apps.count) apps, \(state.settingsItems.count) r\u{00E9}glages, \(state.recents.count) fichiers r\u{00E9}cents, \(state.actions.count) actions. Spotlight compl\u{00E8}te en dessous, sans d\u{00E9}placer la s\u{00E9}lection.")
                .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LearningCard: View {
    @Environment(AppState.self) private var state
    @State private var confirmErase = false

    var body: some View {
        @Bindable var state = state
        SettingsCard(icon: "brain", color: Theme.pine, title: "Apprentissage") {
            Toggle("Mettre l'apprentissage en pause", isOn: $state.learningPaused)
            Picker("M\u{00E9}moire", selection: $state.memoryDays) {
                Text("1 mois").tag(30)
                Text("3 mois").tag(90)
                Text("6 mois").tag(180)
                Text("1 an").tag(365)
            }
            HStack {
                Text("\(state.openingCount) ouverture\(state.openingCount > 1 ? "s" : "") retenue\(state.openingCount > 1 ? "s" : ""), sur ce Mac uniquement.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Button("Tout effacer\u{2026}") { confirmErase = true }
                    .controlSize(.small)
                    .disabled(state.openingCount == 0 && state.forgotten.isEmpty)
            }
            .alert("Effacer tout ce que Lanterne a appris\u{00A0}?", isPresented: $confirmErase) {
                Button("Tout effacer", role: .destructive) { state.eraseAll() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Les ouvertures retenues et la liste des oublis sont supprim\u{00E9}es. Lanterne trouve toujours tout, mais repart de z\u{00E9}ro.")
            }
        }
    }
}

struct ExclusionsCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        SettingsCard(icon: "eye.slash", color: Theme.stone, title: "Exclusions") {
            ForEach(state.excludedFolders, id: \.self) { folder in
                HStack {
                    Image(systemName: "folder").foregroundStyle(Theme.inkSoft)
                    Text(RecentFiles.abbreviate(folder, home: FileManager.default.homeDirectoryForCurrentUser.path))
                        .font(Theme.ui(12.5)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { state.excludedFolders.removeAll { $0 == folder } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkFaint)
                    }
                    .buttonStyle(.plain).help("Ne plus exclure ce dossier")
                }
            }
            Button("Exclure un dossier\u{2026}") { chooseFolder() }.controlSize(.small)
            TextField("Types exclus (extensions, s\u{00E9}par\u{00E9}es par des virgules)", text: $state.excludedTypes)
                .textFieldStyle(.roundedBorder).font(Theme.ui(12))
            Text("Toujours ignor\u{00E9}s\u{00A0}: node_modules, dossiers cach\u{00E9}s et ~/Library.")
                .font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Exclure"
        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.map(\.path).filter { !state.excludedFolders.contains($0) }
        state.excludedFolders += paths
    }
}
