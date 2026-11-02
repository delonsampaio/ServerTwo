import SwiftUI

extension View {
    /// A title centred in the top bar, between a toolbar button (if any) and the
    /// clock. The system navigation title sits at the trailing edge under the
    /// clock instead (it cost a row of height, and read as off-centre), and
    /// watchOS has no principal toolbar slot, so the title is drawn over the
    /// bar: as tall as the top inset, lifted into it.
    func centredTitleBar(_ title: String) -> some View {
        overlay(alignment: .top) {
            GeometryReader { proxy in
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .frame(maxWidth: .infinity)
                    .frame(height: proxy.safeAreaInsets.top)
                    .offset(y: -proxy.safeAreaInsets.top)
                    .accessibilityAddTraits(.isHeader)
                    .allowsHitTesting(false)
            }
        }
    }
}
