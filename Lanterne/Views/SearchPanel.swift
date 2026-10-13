import SwiftUI
import LanterneCore

/// Panneau du raccourci : champ, resultats regroupes, pied avec les touches et la raison de la ligne survolee.
/// Le champ garde le focus : fleches, Retour (ouvrir), Cmd-Retour (Finder), Cmd-C (chemin), Cmd-Suppr (oublier), Cmd-1 a Cmd-9, Echap.
struct SearchPanel: View {
    @Environment(AppState.self) private var state
    @FocusState private var focused: Bool

    var body: some View {
        PanelCard {
            VStack(spacing: 0) {
                field
                Divider().overlay(Theme.line)
                results
                Divider().overlay(Theme.line)
                footer
            }
            .frame(width: AppState.cardSize.width, height: AppState.cardSize.height)
        }
        .padding(AppState.panelMargin)
        .tint(Theme.accent)
        .onAppear { focused = true }
        .onChange(of: state.panelOpenCount) { _, _ in focused = true }
    }

    // MARK: Champ

    private var field: some View {
        @Bindable var state = state
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent)
            TextField("", text: $state.query, prompt: Text("App, r\u{00E9}glage, fichier\u{2026}").foregroundStyle(Theme.inkFaint))
                .textFieldStyle(.plain)
                .font(Theme.ui(20, weight: .medium))
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .onKeyPress(.downArrow) { state.moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { state.moveSelection(by: -1); return .handled }
                .onKeyPress(.escape) {
                    if state.query.isEmpty { state.hidePanel() } else { state.query = "" }
                    return .handled
                }
                .onKeyPress(phases: .down) { press in handle(press) }
            Wordmark.Mini(Brand.displayName)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .return {
            if press.modifiers.contains(.command) { state.revealSelected() } else { state.openSelected() }
            return .handled
        }
        guard press.modifiers == .command else { return .ignored }
        if press.key == .delete || press.key == .deleteForward { state.forgetSelected(); return .handled }
        if press.key == "c" { state.copySelectedPath(); return .handled }
        if let digit = Int(String(press.characters)), (1...9).contains(digit) { state.open(number: digit); return .handled }
        return .ignored
    }

    // MARK: Resultats

    private var results: some View {
        let rows = state.rows
        let numbers = Dictionary(uniqueKeysWithValues: rows.prefix(9).enumerated().map { ($1.id, $0 + 1) })
        let selected = state.selected?.id
        return Group {
            if rows.isEmpty {
                empty
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Pile simple (25 lignes au plus) : identite de ligne = section + cle, pour qu'un element
                        // qui passe des suggestions au meilleur resultat soit redessine.
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(state.sections) { section in
                                sectionHeader(section)
                                ForEach(section.items) { ranked in row(ranked, section.kind, numbers[ranked.id], selected) }
                            }
                            if let further = state.further {
                                sectionHeader(further)
                                ForEach(further.items) { ranked in row(ranked, .further, numbers[ranked.id], selected) }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .scrollIndicators(.never)
                    .onChange(of: state.selected?.id) { _, _ in
                        if let id = rowID(state.selected) { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Identifiant de defilement d'une ligne : sa section et sa cle.
    private func rowID(_ ranked: Ranked?) -> String? {
        guard let ranked else { return nil }
        let kind = state.sections.first { $0.items.contains { $0.id == ranked.id } }?.kind ?? .further
        return kind.rawValue + "|" + ranked.id
    }

    private func row(_ ranked: Ranked, _ kind: ResultSectionKind, _ number: Int?, _ selected: String?) -> some View {
        ResultRow(ranked: ranked, number: number, selected: ranked.id == selected)
            .id(kind.rawValue + "|" + ranked.id)
            .onTapGesture { state.open(ranked) }
            .onHover { inside in
                if inside { state.hoveredKey = ranked.id } else if state.hoveredKey == ranked.id { state.hoveredKey = nil }
            }
    }

    private func sectionHeader(_ section: ResultSection) -> some View {
        HStack(alignment: .firstTextBaseline) {
            SectionHeader(section.kind.title)
            Spacer()
            if section.kind == .suggestions, let line = contextLine {
                Text(line).font(Theme.ui(11)).foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 3)
    }

    /// "vers 9 h - depuis Mail"
    private var contextLine: String? {
        var parts = ["vers \(state.context.hour) h"]
        if let app = state.context.contextApp, let name = AppNames.name(for: app) { parts.append("depuis \(name)") }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(nsImage: GlyphImage.template(Brand.glyph, pointSize: 34, stroke: 2.2))
                .renderingMode(.template).foregroundStyle(Theme.inkFaint)
            if state.query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Tapez quelques lettres : une app, un r\u{00E9}glage, un fichier.")
                    .font(Theme.ui(13.5, weight: .medium)).foregroundStyle(Theme.inkSoft)
                Text("Lanterne retient ce que vous ouvrez, \u{00E0} quelle heure et depuis quelle app.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.inkFaint)
            } else {
                Text("Rien pour \u{00AB}\u{00A0}\(state.query.trimmingCharacters(in: .whitespaces))\u{00A0}\u{00BB}")
                    .font(Theme.ui(13.5, weight: .medium)).foregroundStyle(Theme.inkSoft)
                if state.useSpotlight {
                    Text("Spotlight cherche plus loin\u{2026}").font(Theme.ui(12)).foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
    }

    // MARK: Pied

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint("\u{21A9}", "ouvrir")
            KeyHint("\u{2318}\u{21A9}", "Finder")
            KeyHint("\u{2318}\u{232B}", "oublier")
            Spacer(minLength: 12)
            if let notice = state.notice {
                Text(notice).font(Theme.ui(11.5, weight: .semibold)).foregroundStyle(Theme.accent).lineLimit(1)
            } else if let selected = state.selected, Launcher.isGuarded(selected.item) {
                Text(AppState.guardedNotice).font(Theme.ui(11.5, weight: .semibold)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            } else if let key = state.hoveredKey ?? state.selected?.id, let reason = state.reason(for: key) {
                Text(reason).font(Theme.ui(11.5)).foregroundStyle(Theme.inkFaint).lineLimit(1).truncationMode(.tail)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }
}
