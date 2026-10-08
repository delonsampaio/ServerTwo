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
        let renderer = ImageRenderer(content: MatchRecapCardView(match: match))
        renderer.scale = UIScreen.main.scale
        guard let uiImage = renderer.uiImage else {
            return Image(systemName: "photo")
        }
        return Image(uiImage: uiImage)
    }
}
