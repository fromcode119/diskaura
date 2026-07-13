import Foundation
import Vision
import ImageIO
import UniformTypeIdentifiers

/// Finds LOOK-ALIKE images, not just byte-identical ones — resized copies, re-compressed exports,
/// light edits, and burst shots that exact SHA-256 hashing (the other duplicate mode) can never
/// catch. Uses Vision feature prints on-device: each image becomes a vector, and images whose
/// vectors are within a small distance are grouped. This is the "similar photos" pain Apple Photos'
/// exact-only Duplicates leaves on the table.
enum SimilarImageFinder {
    /// Feature-print distance below which two images count as the same shot. Calibrated on-device:
    /// a resized/re-compressed copy scores ~0.1 while an unrelated image scores ~1.0.
    static let defaultThreshold: Float = 0.35

    static func find(
        in rootURL: URL,
        threshold: Float = defaultThreshold,
        minSizeBytes: Int64 = 10_240,
        exclusions: ExclusionMatcher = ExclusionMatcher(paths: []),
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onProgress: @escaping @Sendable (DuplicateFinderService.Progress) -> Void = { _ in }
    ) async -> [DuplicateGroup] {
        // 1. Collect image files.
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsPackageDescendants]) else { return [] }
        var images: [(url: URL, size: Int64, modified: Date?)] = []
        while let url = enumerator.nextObject() as? URL {
            if isCancelled() { return [] }
            if exclusions.isExcluded(url) || !isImage(url) { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            guard size >= minSizeBytes else { continue }
            images.append((url, size, values?.contentModificationDate))
        }
        guard images.count > 1 else { return [] }

        // 2. Feature-print each image.
        struct Item { let url: URL; let size: Int64; let modified: Date?; let print: VNFeaturePrintObservation }
        var items: [Item] = []
        for (index, image) in images.enumerated() {
            if isCancelled() { return [] }
            if let print = featurePrint(for: image.url) {
                items.append(Item(url: image.url, size: image.size, modified: image.modified, print: print))
            }
            if index % 10 == 0 { onProgress(.init(phase: "Comparing images", done: index, total: images.count)) }
        }

        // 3. Greedy cluster by distance to each cluster's first member.
        var clusters: [[Item]] = []
        for item in items {
            if isCancelled() { return [] }
            var placed = false
            for i in clusters.indices {
                var distance = Float(0)
                if (try? clusters[i][0].print.computeDistance(&distance, to: item.print)) != nil,
                   distance <= threshold {
                    clusters[i].append(item); placed = true; break
                }
            }
            if !placed { clusters.append([item]) }
        }

        // 4. Emit groups with more than one look-alike.
        return clusters
            .filter { $0.count > 1 }
            .map { cluster in
                DuplicateGroup(files: cluster.map { DuplicateFile(url: $0.url, sizeBytes: $0.size, modifiedAt: $0.modified) })
            }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    private static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .rawImage)
    }

    private static func featurePrint(for url: URL) -> VNFeaturePrintObservation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 224,
              ] as CFDictionary) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }
}
