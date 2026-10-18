import SwiftUI

/// A small pill button (the look of `.bordered` + `.controlSize(.small)`:
/// caption text on a light capsule) whose tap area is at least 44 pt tall while
/// the visible pill and the surrounding layout keep their small size. The extra
/// tap area is 9 pt of padding above and below the pill, inside the style's
/// body (so it is part of the button's own hit region and accessibility
/// frame), which the style then gives back to the layout with a negative
/// vertical padding. Works for any label, text or icon (a `ShareLink` too).
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemFill), in: Capsule())
            .padding(.vertical, 9)
            .frame(minWidth: 44)
            .contentShape(Rectangle())
            .padding(.vertical, -9)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
