import UIKit

/// Resizes and compresses a picked photo before it's ever stored in
/// `SavedPlayer.photoData` — this store is CloudKit-synced (roughly a 1MB
/// per-record limit, shared with everything else a `SavedPlayer` carries),
/// and a raw photo-library image can easily run several megabytes. Avatars
/// are shown small everywhere (chips, list rows), so there's no reason to
/// keep more resolution than that.
enum PlayerPhotoProcessor {
    static func process(_ data: Data, maxDimension: CGFloat = 300, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longestEdge = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longestEdge)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
