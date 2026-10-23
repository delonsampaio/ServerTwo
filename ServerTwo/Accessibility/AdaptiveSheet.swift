import SwiftUI

/// Which detents a fixed-height sheet offers. At accessibility text sizes the
/// fixed height cannot be trusted to fit the content, so `.large` is added and
/// the user can pull the sheet up.
enum SheetDetentPolicy {
    /// `@ScaledMetric` also scales DOWN below the default text size, which
    /// would make a fixed-height sheet shorter than its design height. The
    /// detent must never be smaller than the design height.
    static func scaledHeight(design: CGFloat, scaled: CGFloat) -> CGFloat {
        max(design, scaled)
    }

    static func detents(height: CGFloat, isAccessibilitySize: Bool) -> [PresentationDetent] {
        isAccessibilitySize ? [.height(height), .large] : [.height(height)]
    }
}

private struct AdaptiveSheetDetentsModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric private var scaledHeight: CGFloat
    private let designHeight: CGFloat

    init(height: CGFloat) {
        designHeight = height
        _scaledHeight = ScaledMetric(wrappedValue: height, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content.presentationDetents(Set(
            SheetDetentPolicy.detents(height: SheetDetentPolicy.scaledHeight(design: designHeight, scaled: scaledHeight), isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
        ))
    }
}

extension View {
    /// Scales `height` up with Dynamic Type (never below `height`) and applies ONLY the presentation
    /// detents (see `SheetDetentPolicy`). It wraps nothing, so it cannot change
    /// the sheet's layout.
    func adaptiveSheetDetents(height: CGFloat) -> some View {
        modifier(AdaptiveSheetDetentsModifier(height: height))
    }
}

/// At accessibility text sizes the content may be taller than its sheet, so it
/// scrolls (only when it overflows). At every other size it is the content
/// itself, with no `ScrollView`: a vertical `ScrollView` fills all the height it
/// is offered, which would stretch a self-drawn card and top-align its content.
struct AdaptiveScroll<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}
