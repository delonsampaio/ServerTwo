import ActivityKit
import SwiftUI
import WidgetKit

/// Placeholder presentation so the extension target links; the real Lock Screen
/// and Dynamic Island views replace it in the next commit.
struct PickleballLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickleballActivityAttributes.self) { context in
            Text("\(context.state.teamAScore) - \(context.state.teamBScore)")
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.state.teamAScore) - \(context.state.teamBScore)")
                }
            } compactLeading: {
                Text("\(context.state.teamAScore)")
            } compactTrailing: {
                Text("\(context.state.teamBScore)")
            } minimal: {
                Image(systemName: "figure.pickleball")
            }
        }
    }
}
