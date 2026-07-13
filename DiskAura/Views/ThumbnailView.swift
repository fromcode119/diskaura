import SwiftUI
import QuickLookThumbnailing

/// Real file preview (not just a generic Finder icon) via QuickLook's thumbnail
/// generator — the same system Finder/Preview use, so it renders actual image content,
/// PDF first pages, video frames, etc. Falls back to the plain file icon if generation
/// fails (e.g. unreadable file). Used in Duplicate Finder so photos can actually be
/// visually compared before deciding which copy to keep, instead of just a path string.
struct ThumbnailView: View {
    let url: URL
    let size: CGFloat

    @State private var thumbnail: NSImage?

    // Unbounded before — at 4x scale + .all representation, each duplicate-finder
    // thumbnail could be several MB uncompressed; scanning a few hundred duplicate
    // groups pushed the app to ~1GB RSS (confirmed live via `ps`). Both the scale
    // (below) and this cache are now bounded so the app can't grow without limit.
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Theme.panelBackground)
                    .frame(width: size, height: size)
                    .overlay(
                        FileIconView(url: url, size: size * 0.55)
                    )
            }
        }
        .task(id: url) {
            await loadThumbnail()
        }
    }

    @MainActor
    private func loadThumbnail() async {
        let key = "\(url.path)@\(Int(size))" as NSString
        if let cached = Self.cache.object(forKey: key) {
            thumbnail = cached
            return
        }

        // Request .all (not just .thumbnail) for real image/PDF/video-frame content
        // instead of QuickLook's small cached icon-style preview. Scale is capped at 2x
        // (not 4x) — still sharp on Retina, but a 150pt tile at 4x was rendering ~600px
        // images (~5.7MB each uncompressed); 2x keeps it ~360KB while still looking sharp.
        let scale = min(NSScreen.main?.backingScaleFactor ?? 2, 2)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .all
        )

        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return
        }
        Self.cache.setObject(representation.nsImage, forKey: key)
        thumbnail = representation.nsImage
    }
}
