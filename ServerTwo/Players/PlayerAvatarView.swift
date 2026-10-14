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
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
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
    private static let palette: [Color] = [
        .blue, .teal, .indigo, .orange, .pink, .purple, .mint, .brown,
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
