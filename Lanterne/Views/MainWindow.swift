import SwiftUI
import LanterneCore

/// Filtres de la barre laterale des habitudes.
enum HabitFilter: String, CaseIterable, Hashable {
    case all, apps, settings, files, actions, forgotten

    var label: String {
        switch self {
        case .all: "Tout"
        case .apps: "Apps"
        case .settings: "R\u{00E9}glages"
        case .files: "Fichiers et dossiers"
        case .actions: "Actions"
        case .forgotten: "Oubli\u{00E9}s"
        }
    }

    var icon: String {
        switch self {
        case .all: "sparkles"
        case .apps: "square.grid.2x2"
        case .settings: "gearshape"
        case .files: "doc"
        case .actions: "bolt"
        case .forgotten: "eye.slash"
        }
    }

    func includes(_ kind: ItemKind) -> Bool {
        switch self {
        case .all: true
        case .apps: kind == .app
        case .settings: kind == .setting
        case .files: kind == .file || kind == .folder
        case .actions: kind == .action
        case .forgotten: false
        }
    }
}

/// Fenetre "Habitudes" : ce que Lanterne a appris, element par element, et l'oubli d'un clic.
struct MainWindow: View {
    @Environment(AppState.self) private var state
    @State private var filter: HabitFilter = .all

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                UpdateNotice(updater: .shared)
                // En-tete fixe, liste defilante en dessous (la liste ne passe pas sous la barre de titre).
                VStack(alignment: .leading, spacing: 14) {
                    if let conflict = state.conflict { WelcomeCard(conflict: conflict) }
                    if state.needsFolderAccess { FolderAccessCard() }
                    if state.learningPaused { pausedBanner }
                    header
                }
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                ScrollView {
                    Group {
                        if filter == .forgotten { forgottenList } else { habitList }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AmbientBackground())
        }
        .tint(Theme.accent)
        .onAppear { state.refreshConflicts() }
        .onChange(of: HotKeyController.shared.shortcut) { _, _ in state.refreshConflicts() }
    }

    // MARK: Barre laterale

    private var sidebar: some View {
        let profiles = state.habits.ordered
        let week = profiles.reduce(0) { $0 + $1.weekCount }
        return VStack(alignment: .leading, spacing: 0) {
            Wordmark(Brand.displayName)
                .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 14)
            VStack(alignment: .leading, spacing: 6) {
                stat("\u{00C9}l\u{00E9}ments appris", profiles.count)
                stat("Ouvertures retenues", state.openingCount)
                stat("Cette semaine", week)
            }
            .padding(.horizontal, 18).padding(.bottom, 12)
            List(HabitFilter.allCases.filter { $0 != .forgotten || !state.forgotten.isEmpty }, id: \.self, selection: $filter) { f in
                Label(f.label, systemImage: f.icon)
                    .font(Theme.ui(13, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Spacer(minLength: 0)
            Button { state.showPanel() } label: {
                Label("Chercher", systemImage: "magnifyingglass").font(Theme.ui(12.5, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.accent)
            .padding(.horizontal, 18).padding(.bottom, 8)
            ShortcutFooter(HotKeyController.shared.shortcut)
        }
        .frame(width: 210)
        .background(Theme.sidebar)
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label).font(Theme.ui(12)).foregroundStyle(Theme.inkSoft)
            Spacer()
            Text("\(value)").font(Theme.ui(12.5, weight: .bold)).foregroundStyle(Theme.ink).monospacedDigit()
        }
    }

    // MARK: Contenu

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(filter == .forgotten ? "Oubli\u{00E9}s" : "Ce que Lanterne a appris")
                .font(Theme.display(24)).foregroundStyle(Theme.ink)
            Text(filter == .forgotten
                 ? "Lanterne ne les apprend plus et ne les sugg\u{00E8}re plus. Les apps et r\u{00E9}glages restent trouvables."
                 : "Du plus habituel au moins habituel. Tout reste sur ce Mac ; chaque \u{00E9}l\u{00E9}ment s'oublie d'un clic.")
                .font(Theme.ui(12.5)).foregroundStyle(Theme.inkSoft)
        }
    }

    private var pausedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill").foregroundStyle(Theme.accent)
            Text("Apprentissage en pause : Lanterne trouve toujours, mais ne retient plus rien.")
                .font(Theme.ui(12.5, weight: .medium)).foregroundStyle(Theme.ink)
            Spacer()
            PillButton("Reprendre") { state.learningPaused = false }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.item, style: .continuous).fill(Theme.accentSelection))
    }

    @ViewBuilder
    private var habitList: some View {
        let profiles = state.habits.ordered.filter { filter.includes($0.kind) }
        if profiles.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 8) {
                ForEach(profiles, id: \.key) { profile in HabitRow(profile: profile) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(nsImage: GlyphImage.plate(Brand.palette, glyph: Brand.glyph, pixels: 112))
                .resizable().frame(width: 56, height: 56)
            Text(filter == .all ? "Rien d'appris pour l'instant" : "Rien d'appris dans cette cat\u{00E9}gorie")
                .font(Theme.display(17)).foregroundStyle(Theme.ink)
            Text("Appuyez sur \(HotKeyController.shared.shortcut.display), tapez trois lettres, \u{21A9}. Lanterne retient ce que vous ouvrez, \u{00E0} quelle heure et depuis quelle app, et le propose au bon moment.")
                .font(Theme.ui(12.5)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var forgottenList: some View {
        LazyVStack(spacing: 8) {
            ForEach(state.forgotten.sorted(), id: \.self) { key in
                HStack(spacing: 12) {
                    if let item = state.index.item(forKey: key) {
                        Image(nsImage: Icons.image(for: item)).resizable().frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "eye.slash").frame(width: 28, height: 28).foregroundStyle(Theme.inkFaint)
                    }
                    Text(state.title(forKey: key)).font(Theme.ui(13, weight: .medium)).foregroundStyle(Theme.ink)
                    Spacer()
                    PillButton("R\u{00E9}apprendre") { state.unforget(key) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.item, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.item, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            }
        }
    }
}

/// Un element appris : icone, titre, raison, apps d'origine, bande des 24 heures, "Oublier".
struct HabitRow: View {
    @Environment(AppState.self) private var state
    let profile: HabitProfile
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 14) {
            icon.frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.title).font(Theme.ui(13.5, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                // Apps d'origine en pastilles, pas dans la phrase.
                if let reason = state.habits.explain(key: profile.key, now: Date(), appName: { _ in nil }) {
                    Text(reason).font(Theme.ui(11.5)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                let contexts = profile.topContexts(limit: 3).compactMap { c in AppNames.name(for: c.bundle).map { ($0, c.count) } }
                if !contexts.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(contexts, id: \.0) { name, count in
                            Chip("depuis \(name) \u{00D7}\(count)", color: Theme.inkSoft)
                        }
                    }
                }
            }
            Spacer(minLength: 12)
            HabitStrip(counts: profile.hourCounts, currentHour: Calendar.current.component(.hour, from: Date()))
            PillButton("Oublier") { state.forget(profile.key) }
                .help("Effacer ce que Lanterne a appris de cet \u{00E9}l\u{00E9}ment et ne plus l'apprendre")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.item, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.item, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private var icon: some View {
        if let item = state.index.item(forKey: profile.key) ?? state.orphan(profile) {
            Image(nsImage: Icons.image(for: item)).resizable().interpolation(.high)
        } else {
            Image(systemName: "questionmark.square.dashed").font(.system(size: 20)).foregroundStyle(Theme.inkFaint)
        }
    }
}
