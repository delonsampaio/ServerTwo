import SwiftUI

/// The label of a small pill button (the look of `.bordered` +
/// `.controlSize(.small)`: caption text on a light capsule) whose tap area is
/// 44 pt tall while the visible pill and the surrounding layout keep their
/// small size. The 9 pt of extra tap area above and below the pill is padding
/// inside the label (so it is part of the button's own hit region), and the
/// button gives that space back to the layout with `.padding(.vertical, -9)`
/// (see `pillButtonLayout()`). Use with `.buttonStyle(.plain)`.
struct PillButtonLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemFill), in: Capsule())
            .padding(.vertical, 9)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Pairs with `PillButtonLabel`: takes back the 9 pt tap-area padding so
    /// the pill occupies the same layout space as a plain small button.
    func pillButtonLayout() -> some View {
        buttonStyle(.plain).padding(.vertical, -9)
    }
}
