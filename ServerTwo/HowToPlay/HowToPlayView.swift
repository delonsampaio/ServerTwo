import SwiftUI

/// A comprehensive, on-demand pickleball rules reference, reachable from
/// Settings. Content verified across multiple sources (USA Pickleball's
/// own rules summary plus several independent explainer sites) as of
/// October 2026, including the 2021 let-serve rule removal and the
/// current two-bounce / non-volley-zone mechanics.
struct HowToPlayView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                ruleCard(
                    icon: "target",
                    tint: .green,
                    title: "The Basics"
                ) {
                    Text("Pickleball is played on a badminton-sized court with a net, using solid paddles and a plastic, perforated ball. It can be played one-on-one (singles) or two-on-two (doubles) — Server Two supports both.")
                }

                ruleCard(
                    icon: "arrow.up.forward",
                    tint: .blue,
                    title: "Serving"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Served underhand, below waist height, with the paddle moving in an upward arc. The serve travels diagonally and must land in the opposite service box — it can't land in the kitchen (below) or on its line.")
                        Text("A serve that clips the net but still lands in the correct box is live play, not a replay — that changed in 2021.")
                            .foregroundStyle(.secondary)
                    }
                }

                ruleCard(
                    icon: "arrow.up.and.down",
                    tint: .purple,
                    title: "The Two-Bounce Rule"
                ) {
                    Text("After the serve, the receiving side must let the ball bounce before returning it — and the serving side must let that return bounce too. Only after both of those bounces can either side start volleying (hitting the ball out of the air). This is what stops a team from serving and immediately rushing the net to end the point.")
                }

                ruleCard(
                    icon: "square.split.2x1",
                    tint: .orange,
                    title: "The Non-Volley Zone (\"The Kitchen\")"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        kitchenDiagram
                        Text("A 7-foot zone on each side of the net. You can't volley the ball while any part of you is touching this zone or its line — even if your momentum carries you in right after the volley. You can still step in to play a ball that's already bounced.")
                    }
                }

                ruleCard(
                    icon: "number",
                    tint: .red,
                    title: "Scoring"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Standard games are played to 11 points, win by 2 — only the serving side can score. Server Two also supports games to 15 or 21, and a rally-scoring format where either side can score, if you'd rather play that way.")
                        Text("In doubles, the score is called as three numbers: serving team's score, receiving team's score, then which server is up (1 or 2). Each team gets two servers per turn before a side-out — except the very first serve of the match, which starts at server 2 (\"0-0-2\"), since there's no partner who already lost a turn yet. Server Two tracks all of this automatically.")
                            .foregroundStyle(.secondary)
                    }
                }

                ruleCard(
                    icon: "person.fill",
                    tint: .teal,
                    title: "Singles Differences"
                ) {
                    Text("The two-bounce rule, the kitchen, and serve mechanics are all the same. What changes: there's only one server (no server number to track), you serve from the right side when your score is even and the left when it's odd, and a single fault is an immediate side-out.")
                }
            }
            .padding()
        }
        .navigationTitle("How to Play")
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("A quick reference for pickleball's core rules — serving, scoring, and the two rules that trip up most beginners.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func ruleCard<Content: View>(
        icon: String,
        tint: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.headline)
                Text(title)
                    .font(.headline)
            }
            content()
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// A simplified top-down diagram: backcourt on each side, with the
    /// 7-foot non-volley zone flanking the net in the middle. Drawn with
    /// native shapes (matching CourtDiagramView's approach) rather than an
    /// image, so it stays crisp at any size and themes automatically.
    private var kitchenDiagram: some View {
        HStack(spacing: 0) {
            backcourt
            kitchenStrip
            Rectangle()
                .fill(.secondary)
                .frame(width: 2)
            kitchenStrip
            backcourt
        }
        .frame(height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.secondary, lineWidth: 1)
        )
    }

    private var backcourt: some View {
        Color.clear.frame(maxWidth: .infinity)
    }

    private var kitchenStrip: some View {
        Color.orange.opacity(0.25)
            .frame(width: 36)
            .overlay(
                Text("KITCHEN")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
            )
    }
}

#Preview {
    NavigationStack {
        HowToPlayView()
    }
}
