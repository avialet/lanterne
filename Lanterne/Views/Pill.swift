import SwiftUI
import LanterneCore

/// Bouton en pastille : principal (comme sur les sites) ou discret.
struct Pill: View {
    let title: String
    var primary = false

    init(_ title: String, primary: Bool = false) {
        self.title = title
        self.primary = primary
    }

    var body: some View {
        Text(title)
            .font(Theme.ui(12, weight: .semibold))
            .foregroundStyle(primary ? Theme.accentPrimaryButtonForeground : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(primary ? Theme.accentPrimaryButtonBackground : Theme.ink.opacity(0.07)))
            .fixedSize()
            .contentShape(Capsule())
    }
}

struct PillButton: View {
    let title: String
    var primary = false
    let action: () -> Void

    init(_ title: String, primary: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.primary = primary
        self.action = action
    }

    var body: some View {
        Button(action: action) { Pill(title, primary: primary) }.buttonStyle(.plain)
    }
}
