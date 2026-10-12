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
                    Circle().fill(Color.accentColor)
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
}

#Preview {
    let player = SavedPlayer(name: "Delon S.")
    return PlayerAvatarView(player: player, size: 80)
}
