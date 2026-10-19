import SwiftUI

extension View {
    /// Grows the hit region and accessibility frame of a small element to at
    /// least 44 pt tall without growing the layout: the vertical padding is
    /// inside the hit region and then given back with a negative padding
    /// (the same technique as `PillButtonStyle`).
    func tapAreaPadding(_ extra: CGFloat = 14) -> some View {
        padding(.vertical, extra)
            .contentShape(Rectangle())
            .padding(.vertical, -extra)
    }

    /// For a `Button` label: the padding and the hit shape go on the label
    /// (use this inside the button's label closure), and `tapAreaGiveBack`
    /// goes on the Button itself, so the Button's own frame keeps the grown
    /// tap area while the layout does not grow.
    func tapAreaLabel(_ extra: CGFloat = 14) -> some View {
        padding(.vertical, extra).contentShape(Rectangle())
    }

    func tapAreaGiveBack(_ extra: CGFloat = 14) -> some View {
        padding(.vertical, -extra)
    }
}
