import SwiftUI

/// A team name that shows the longest form that fits the width it is given:
/// the full name, then first name and last initial ("Delon S. & Mike R."),
/// then first names (`WatchMatchPlayers.teamNameVariants`). Only the shortest
/// form may wrap (up to `lines`) or be cut off. `prefix` ("vs ") and `suffix`
/// (" serving") go around every form, so they count towards the fit.
struct FittingTeamName: View {
    let variants: [String]
    var prefix = ""
    var suffix = ""
    var lines = 1
    var minimumScale: CGFloat = 0.75

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(variants.dropLast(), id: \.self) { name in
                Text(prefix + name + suffix).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            Text(prefix + (variants.last ?? "") + suffix)
                .lineLimit(lines)
                .minimumScaleFactor(minimumScale)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
