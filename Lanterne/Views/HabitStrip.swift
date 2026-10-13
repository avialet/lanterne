import SwiftUI
import LanterneCore

/// Bande des 24 heures : une case par heure, d'autant plus dense que l'element y est souvent ouvert ;
/// l'heure courante est cerclee d'encre.
struct HabitStrip: View {
    let counts: [Int]
    var currentHour: Int? = nil
    var cell: CGFloat = 6
    var height: CGFloat = 18

    var body: some View {
        let top = max(1, counts.max() ?? 1)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 1.5) {
                ForEach(0..<24, id: \.self) { hour in
                    let value = hour < counts.count ? counts[hour] : 0
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(value == 0 ? Theme.ink.opacity(0.06) : Theme.accent.opacity(0.25 + 0.75 * Double(value) / Double(top)))
                        .frame(width: cell, height: height)
                        .overlay(RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .strokeBorder(Theme.ink.opacity(hour == currentHour ? 0.55 : 0), lineWidth: 1))
                }
            }
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text("\(hour) h").font(Theme.ui(9, weight: .medium)).foregroundStyle(Theme.inkFaint)
                        .frame(width: 6 * (cell + 1.5), alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heures d'ouverture")
    }
}
