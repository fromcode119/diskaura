import SwiftUI
import AppKit

/// Real Finder icon for a path, cached per-path since NSWorkspace icon lookups aren't free.
struct FileIconView: View {
    let url: URL
    let size: CGFloat

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()

    private var icon: NSImage {
        let key = url.path as NSString
        if let cached = Self.cache.object(forKey: key) {
            return cached
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        Self.cache.setObject(image, forKey: key)
        return image
    }

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
