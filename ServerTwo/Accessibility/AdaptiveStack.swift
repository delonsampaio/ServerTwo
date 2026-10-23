import SwiftUI

/// A row at normal text sizes that stacks into a column at accessibility sizes,
/// for button pairs and label/value pairs that no longer fit side by side.
/// `AnyLayout` keeps the children's identity (and state) across the switch.
/// Don't put a `Spacer` inside: it would add a gap in the vertical layout.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let rowAlignment: VerticalAlignment
    private let columnAlignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let content: Content

    init(
        rowAlignment: VerticalAlignment = .center,
        columnAlignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.rowAlignment = rowAlignment
        self.columnAlignment = columnAlignment
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: columnAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: rowAlignment, spacing: spacing))
        layout { content }
    }
}
