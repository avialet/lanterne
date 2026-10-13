import SwiftUI
import LanterneCore

/// Ligne de resultat : vraie icone, titre aux lettres trouvees en accent, chemin ou genre, Cmd-1 a Cmd-9.
struct ResultRow: View {
    let ranked: Ranked
    let number: Int?
    let selected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(nsImage: Icons.image(for: ranked.item)).resizable().interpolation(.high)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.highlighted(ranked.item.title, ranges: ranked.match?.ranges ?? []))
                    .font(Theme.ui(13.5, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(subtitle).font(Theme.ui(11)).foregroundStyle(Theme.inkSoft).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let number {
                Text("\u{2318}\(number)").font(Theme.ui(11, weight: .semibold))
                    .foregroundStyle(selected ? Theme.inkSoft : Theme.inkFaint)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
            .fill(selected ? Theme.accentSelection : .clear))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var subtitle: String {
        guard let keyword = ranked.match?.keyword else { return kindSubtitle }
        return kindSubtitle + " \u{00B7} \u{00AB}\u{00A0}" + keyword + "\u{00A0}\u{00BB}"
    }

    private var kindSubtitle: String {
        switch ranked.item.kind {
        case .app: "App \u{00B7} " + ranked.item.subtitle
        case .setting: ranked.item.subtitle
        case .file, .folder: ranked.item.subtitle
        case .action: "Action de " + ranked.item.subtitle
        }
    }

    /// Titre dont les caracteres `ranges` sont en accent, en gras.
    static func highlighted(_ title: String, ranges: [Range<Int>]) -> AttributedString {
        guard !ranges.isEmpty else { return AttributedString(title) }
        var out = AttributedString()
        var offset = 0
        var current = ""
        var currentOn = false
        func flush() {
            guard !current.isEmpty else { return }
            var part = AttributedString(current)
            if currentOn {
                part.foregroundColor = Theme.accent
                part.font = Theme.ui(13.5, weight: .bold)
            }
            out += part
            current = ""
        }
        for character in title {
            let on = ranges.contains { $0.contains(offset) }
            if on != currentOn { flush(); currentOn = on }
            current.append(character)
            offset += 1
        }
        flush()
        return out
    }
}
