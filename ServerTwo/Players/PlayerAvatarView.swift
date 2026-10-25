import SwiftUI
import UIKit
import PickleballKit

/// Shared avatar used everywhere a player's identity is shown — Quick
/// Start, Manage Players, suggestion chips, ScoringView, and
/// PlayerDetailView. Renders the player's photo if one is set, otherwise
/// falls back to a colored circle with their initials.
struct PlayerAvatarView: View {
    let player: SavedPlayer
    var size: CGFloat = 44

    // The avatar grows with Dynamic Type (so its initials do too) but stops at
    // 1.6x, which keeps rows and chips from being taken over by it.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    private var scaledSize: CGFloat { size * max(1, min(textScale, 1.6)) }

    var body: some View {
        Group {
            if let photoData = player.photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Self.color(for: player.id))
                    Text(Self.initials(for: player.name))
                        .font(.system(size: scaledSize * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: scaledSize, height: scaledSize)
        .clipShape(Circle())
    }

    static func initials(for name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// A fixed, deterministic palette rather than hashing straight to a
    /// hue — every color here is tuned to stay legible with white text,
    /// which an arbitrary hashed hue can't guarantee. Keyed off the
    /// player's stable `id` (not their name, which can be edited) so a
    /// given person's color never changes from a rename.
    ///
    /// The same eight hues in the same order as before (blue, teal, indigo,
    /// orange, pink, purple, mint, brown; the index mapping is untouched),
    /// darkened until the white initials reach at least 5.4:1 (the system colours
    /// were 2.1 to 4.1:1; the audit measures rendered pixels, so there is margin
    /// over 4.5). White-on-fill ratios: blue #0A5FD0 5.90, teal #0E6E7D 5.92,
    /// indigo #4B49C4 6.89, orange #A65200 5.49, pink #C71F45 5.66, purple
    /// #8636B8 6.49, mint #0A7358 5.82, brown #775B3B 6.28. Fixed sRGB
    /// values (not adaptive) so a person keeps the same colour in light and
    /// dark mode.
    private static let palette: [Color] = [
        Color(srgbHex: 0x0A5FD0), Color(srgbHex: 0x0E6E7D), Color(srgbHex: 0x4B49C4),
        Color(srgbHex: 0xA65200), Color(srgbHex: 0xC71F45), Color(srgbHex: 0x8636B8),
        Color(srgbHex: 0x0A7358), Color(srgbHex: 0x775B3B),
    ]

    /// `UUID.hashValue` is seeded randomly per process launch (same as
    /// every `Hashable` conformance in Swift, for hash-flooding
    /// resistance) — it would pick a different color for the same player
    /// every time the app relaunches. Summing the UUID's own bytes instead
    /// gives an index that's stable across launches and devices.
    private static func color(for id: UUID) -> Color {
        let byteSum = withUnsafeBytes(of: id.uuid) { bytes in
            bytes.reduce(0) { $0 &+ Int($1) }
        }
        return palette[byteSum % palette.count]
    }
}

#Preview {
    let player = SavedPlayer(name: "Delon S.")
    return PlayerAvatarView(player: player, size: 80)
}
