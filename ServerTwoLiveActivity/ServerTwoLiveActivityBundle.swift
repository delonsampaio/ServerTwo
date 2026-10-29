import SwiftUI
import WidgetKit

/// The extension's only widget is the match Live Activity. There is no Home
/// Screen widget on purpose (the Xcode template's placeholder one was dropped).
@main
struct ServerTwoLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        PickleballLiveActivity()
    }
}
