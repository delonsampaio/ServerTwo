import SwiftUI

/// The app's named colours, defined in `Assets.xcassets` (one colour set each,
/// light and dark where they differ; Xcode generates `Color.accentText`,
/// `.secondaryText`, `.winGreen`, `.winGreenText`, `.lossRed`, `.errorRed`,
/// `.tagOrange` and `.orangeText` from them) and documented here so there is
/// ONE place to tune them. Each value was tuned to a measured WCAG contrast ratio (sRGB
/// relative luminance, python script, not eyeballed) because the strict
/// accessibility audit (`AccessibilityAuditUITests`) rejects anything under
/// 4.5:1 for text. The surfaces used for the checks:
/// light: white, system grouped background #F2F2F7, a grey card #E5E5EA;
/// dark: black, card #1C1C1E, elevated card / thick fill #2C2C2E.
extension Color {
    // The global accent is the `AccentColor` colour set (also the app tint,
    // so there is no property for it). It is used BEHIND white text
    // (prominent buttons, the Flip Coin capsule, badges), so it is as light as
    // white-on-accent allows:
    // light #0A64DC: white 5.43:1, on #F2F2F7 4.86:1;
    // dark #2D6BF9: white 4.58:1 and on black 4.58:1 (the only band where
    // white-on-accent and accent-on-black both pass; system toolbar buttons
    // sit on black, and so does the selected tab). The system blue it
    // replaces is 4.02:1 on white. A darker dark accent (#2563EB, white 5.17)
    // was tried and made the audit rate the glass prominent buttons worse.
    // Accent-coloured TEXT on cards uses `accentText`.

    // Accent-coloured TEXT (a lighter blue in dark mode, because no single
    // blue gives white-on-accent and accent-on-dark-card 4.5:1 at once; the
    // accent itself is only 3.71:1 on a #1C1C1E card):
    // light #0B57C4: white 6.61, #F2F2F7 5.93, on the accent's 12 % tint
    // over #F2F2F7 5.02:1;
    // dark #85BEFF: black 10.81, #1C1C1E 8.76, #2C2C2E 7.17, the Rename /
    // Rematch pill fill #3B3B3E 5.74, the accent's 12 % tint (the Me badge)
    // over #1C1C1E 7.85:1.

    // Secondary captions, replacing `.secondary` / `.tertiary` text (the
    // system secondary is roughly 3.4 to 4.4:1 on grouped and material
    // surfaces). Still clearly quieter than `.primary`:
    // light #5C5C61: white 6.65, #F2F2F7 5.96, #E5E5EA 5.30:1;
    // dark #AEAEB4: black 9.51, #1C1C1E 7.71, #2C2C2E 6.31:1.

    // Fill of a win badge / recent-form dot, always under WHITE text:
    // #1E7B34, white 5.33:1 (the system green is 2.22:1).

    // The letter of a win badge drawn on a `winGreen` 15 % tint circle:
    // light #14632A: 5.41:1 on the tint over #F2F2F7, 4.86 over #E5E5EA;
    // dark #5BD672: 8.06:1 on the tint over #1C1C1E.

    // Fill of a loss badge / recent-form dot, always under WHITE text:
    // #C62828, white 5.62:1 (the system red #FF3B30 is 3.55:1).

    // Red TEXT and outlines (the reason / problem lines, the loss letter on a
    // `lossRed` 15 % tint circle, the Delete Match outline):
    // light #A8141A: white 7.55, #F2F2F7 6.77, #E5E5EA 6.02, on the tint over
    // #F2F2F7 5.37:1;
    // dark #FF7A72: black 8.28, #1C1C1E 6.71, #2C2C2E 5.49, on the tint over
    // #1C1C1E 6.10:1.

    // Fill of the Match Detail "Closest Game" tag, under WHITE text:
    // #B45309, white 5.02:1 (the system orange is 2.20:1).

    // Orange TEXT (the win streak): light #A84A00 on #F2F2F7 5.16:1, white
    // 5.76:1; dark #FFA640 on #1C1C1E 8.73:1, #2C2C2E 7.15:1.

    /// Opacity of the win / loss badge tint circles. Low enough that the
    /// letter colours above keep 4.5:1 on top of them.
    static let resultBadgeTintOpacity = 0.15

    /// An opaque sRGB colour from a 0xRRGGBB value.
    init(srgbHex: UInt32) {
        self.init(
            .sRGB,
            red: Double((srgbHex >> 16) & 0xFF) / 255,
            green: Double((srgbHex >> 8) & 0xFF) / 255,
            blue: Double(srgbHex & 0xFF) / 255
        )
    }
}
