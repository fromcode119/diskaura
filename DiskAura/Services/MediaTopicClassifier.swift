import Foundation
import Vision
import ImageIO
import UniformTypeIdentifiers
import CoreServices

/// Figures out what an image file actually IS by reading it, not by parsing its (meaningless)
/// name. Camera files like `DSC00776.ARW` carry zero words, so name-based grouping dumps them
/// all into "Other". This reads the file two ways, fully on-device (no network, no model
/// download):
///   1. Content — Apple's Vision scene classifier looks at the pixels and returns a topic
///      ("Nature", "Food", "Documents", …). This is the "scan the content" path.
///   2. Metadata — the EXIF capture date groups photos by the month they were actually taken.
/// RAW formats (ARW/CR2/NEF/DNG…) are handled via ImageIO's fast embedded thumbnail, so we
/// never fully decode a 25 MB raw just to classify it.
enum MediaTopicClassifier {
    /// True for anything ImageIO can read as a picture, including camera RAW.
    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .rawImage)
    }

    /// A nested photo folder ("Photos/People", "Photos/Screenshots", …) chosen with the RIGHT
    /// priority: a person present wins over the scenery behind them (a woman outdoors is
    /// "People", not "Nature"), screenshots are detected from macOS metadata, and document-like
    /// images become "Scans" rather than being confused with real documents. Always returns a
    /// path so images never fall through to the LLM (keeping organize fast).
    static func photoFolder(for url: URL) -> String {
        if isScreenshot(url) { return "Photos/Screenshots" }
        let labels = scoredLabels(for: url)
        func has(_ keys: [String], _ minConfidence: Float = 0.25) -> Bool {
            labels.contains { label in
                label.confidence >= minConfidence && keys.contains { label.id.contains($0) }
            }
        }
        // Priority order matters — subjects (people/animals/food) beat background scenery.
        if has(["person", "people", "face", "portrait", "adult", "child", "selfie", "crowd", "wedding", "baby"]) { return "Photos/People" }
        if has(["dog", "cat", "animal", "bird", "horse", "pet", "wildlife", "fish"]) { return "Photos/Animals" }
        if has(["food", "meal", "dish", "fruit", "vegetable", "drink", "dessert", "cuisine", "coffee"]) { return "Photos/Food" }
        if has(["document", "text", "receipt", "paper", "page", "menu", "whiteboard"], 0.30) { return "Photos/Scans" }
        if has(["car", "vehicle", "boat", "airplane", "bicycle", "motorcycle", "train"]) { return "Photos/Vehicles" }
        if has(["building", "architecture", "city", "street", "room", "interior", "monument", "bridge", "furniture"]) { return "Photos/Places" }
        if has(["beach", "mountain", "sky", "tree", "plant", "flower", "landscape", "water", "sea", "lake", "forest", "sunset", "snow", "garden", "field"]) { return "Photos/Nature" }
        if let month = dateTopic(for: url) { return "Photos/\(month)" }
        return "Photos"
    }

    /// Screenshots: macOS stamps `kMDItemIsScreenCapture` on them; also catch common filename
    /// patterns from macOS and popular tools as a fallback.
    private static func isScreenshot(_ url: URL) -> Bool {
        if let item = MDItemCreate(nil, url.path as CFString),
           let flag = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? NSNumber,
           flag.boolValue { return true }
        let name = url.lastPathComponent.lowercased()
        return ["screenshot", "screen shot", "screen_shot", "cleanshot", "captura", "снимок экрана"]
            .contains { name.contains($0) }
    }

    /// Vision labels with confidence, lowercased, for priority matching.
    private static func scoredLabels(for url: URL) -> [(id: String, confidence: Float)] {
        guard let cg = thumbnailCGImage(for: url) else { return [] }
        let request = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        return (request.results ?? [])
            .filter { $0.confidence >= 0.15 }
            .map { (id: $0.identifier.lowercased(), confidence: $0.confidence) }
    }

    /// Content topic from the pixels via Vision. Returns a coarse, human-friendly bucket
    /// ("Nature", "Animals", "Food", "Documents", "Vehicles", "Places") or nil when nothing
    /// is confident enough to name.
    static func contentTopic(for url: URL) -> String? {
        guard let cg = thumbnailCGImage(for: url) else { return nil }
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])
        let candidates = (request.results ?? [])
            .filter { $0.confidence >= 0.20 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(8)
        for observation in candidates {
            if let bucket = bucket(for: observation.identifier) { return bucket }
        }
        return nil
    }

    /// Top raw Vision labels (e.g. "beach", "dog", "document") for feeding an LLM — richer than
    /// the coarse bucket, so the model can name a specific folder. Empty when nothing is confident.
    static func rawLabels(for url: URL, max: Int = 4) -> [String] {
        guard let cg = thumbnailCGImage(for: url) else { return [] }
        let request = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        return (request.results ?? [])
            .filter { $0.confidence >= 0.20 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(max)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    /// Metadata topic: the month the shot was taken (EXIF), falling back to file dates.
    static func dateTopic(for url: URL) -> String? {
        guard let date = captureDate(for: url) ?? fileDate(for: url) else { return nil }
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }

    // MARK: - Vision label → coarse bucket

    /// Vision's taxonomy has thousands of fine labels ("golden_retriever", "espresso"); we fold
    /// them into a handful of folder-worthy buckets by matching keywords in the label.
    private static let buckets: [(name: String, keys: [String])] = [
        ("Documents", ["document", "text", "paper", "receipt", "menu", "page", "book", "newspaper", "letter", "whiteboard", "screenshot"]),
        ("Food", ["food", "meal", "fruit", "vegetable", "drink", "beverage", "coffee", "dessert", "dish", "cuisine", "bread", "cake", "pizza"]),
        ("Animals", ["dog", "cat", "bird", "animal", "horse", "fish", "wildlife", "pet", "insect", "reptile", "mammal"]),
        ("Vehicles", ["car", "vehicle", "bicycle", "motorcycle", "boat", "ship", "airplane", "aircraft", "train", "bus", "truck"]),
        ("Nature", ["beach", "mountain", "sky", "cloud", "tree", "plant", "flower", "forest", "landscape", "sunset", "sunrise", "water", "lake", "sea", "ocean", "grass", "garden", "snow", "field", "river", "waterfall", "desert"]),
        ("People", ["person", "people", "portrait", "face", "crowd", "wedding", "group"]),
        ("Places", ["building", "architecture", "house", "city", "street", "room", "indoor", "furniture", "interior", "office", "bridge", "tower", "monument"]),
    ]

    private static func bucket(for identifier: String) -> String? {
        let id = identifier.lowercased()
        for bucket in buckets where bucket.keys.contains(where: { id.contains($0) }) {
            return bucket.name
        }
        return nil
    }

    // MARK: - ImageIO helpers

    private static func thumbnailCGImage(for url: URL, maxPixel: Int = 256) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static let exifFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func captureDate(for url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = exifFormatter.date(from: original) {
            return date
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let dt = tiff[kCGImagePropertyTIFFDateTime] as? String,
           let date = exifFormatter.date(from: dt) {
            return date
        }
        return nil
    }

    private static func fileDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }
}
