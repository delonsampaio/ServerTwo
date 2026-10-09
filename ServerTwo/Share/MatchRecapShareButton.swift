import SwiftUI
import PickleballKit

struct MatchRecapShareButton: View {
    let match: MatchRecord
    @State private var renderedImage: Image?

    var body: some View {
        Group {
            if let renderedImage {
                ShareLink(item: renderedImage, preview: SharePreview("Match Result", image: renderedImage)) {
                    Image(systemName: "square.and.arrow.up")
                }
            } else {
                ProgressView()
            }
        }
        .task {
            renderedImage = renderCardImage()
        }
    }

    @MainActor
    private func renderCardImage() -> Image {
        // Force light mode: the rendered card is shared outside the app, so its
        // appearance must be deterministic rather than inheriting whatever
        // theme the app happens to be in. `UIScreen.main` is soft-deprecated
        // and there's no View context here to read an environment value from,
        // so pin the scale at 3 instead.
        let renderer = ImageRenderer(content: MatchRecapCardView(match: match).environment(\.colorScheme, .light))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else {
            return Image(systemName: "photo")
        }
        return Image(uiImage: uiImage)
    }
}
