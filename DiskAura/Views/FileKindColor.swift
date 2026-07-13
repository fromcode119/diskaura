import SwiftUI

/// Colors sunburst segments by content KIND (photos, video, documents, apps, code, audio,
/// archives) — DaisyDisk's actual approach. The ring previously reused `Theme.tagColor`
/// (Keep/Clean/Archive/System), which made almost every segment identical green since
/// nearly everything in a normal scan is tagged "Keep" — reading as flat/monochrome even
/// though it was technically colored. Kind-based color gives the at-a-glance variety.
enum FileKindColor {
    private static let appColor = Color(red: 0.36, green: 0.55, blue: 1.00)
    private static let imageColor = Color(red: 1.00, green: 0.70, blue: 0.20)
    private static let videoColor = Color(red: 1.00, green: 0.32, blue: 0.42)
    private static let audioColor = Color(red: 0.98, green: 0.45, blue: 0.85)
    private static let documentColor = Color(red: 0.30, green: 0.78, blue: 0.86)
    private static let codeColor = Color(red: 0.62, green: 0.48, blue: 1.00)
    private static let archiveColor = Color(red: 0.70, green: 0.55, blue: 0.40)
    private static let systemColor = Color(red: 0.55, green: 0.58, blue: 0.64)
    private static let folderColor = Color(red: 0.40, green: 0.68, blue: 0.98)
    private static let otherColor = Color(red: 0.45, green: 0.80, blue: 0.55)

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "raw", "cr2", "nef", "dng", "tiff", "bmp", "webp", "svg", "psd", "ai"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv", "webm"]
    private static let audioExtensions: Set<String> = ["mp3", "wav", "m4a", "aac", "flac", "aiff", "ogg"]
    private static let documentExtensions: Set<String> = ["pdf", "doc", "docx", "pages", "txt", "rtf", "key", "numbers", "xls", "xlsx", "ppt", "pptx", "md"]
    private static let codeExtensions: Set<String> = ["swift", "js", "ts", "py", "rb", "go", "rs", "c", "cpp", "h", "java", "json", "yml", "yaml", "html", "css", "sh"]
    private static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "dmg", "pkg", "rar", "7z", "iso"]

    private static let codeFolderNames: Set<String> = ["node_modules", ".git", "Pods", "target", ".build", "DerivedData", "vendor"]

    static func color(for node: FileNode) -> Color {
        let name = node.name

        if name.hasSuffix(".app") { return appColor }
        if node.tag == .system { return systemColor }

        if node.isDirectory {
            if codeFolderNames.contains(name) { return codeColor }
            switch name {
            case "Applications": return appColor
            case "Pictures", "Photos": return imageColor
            case "Movies": return videoColor
            case "Music": return audioColor
            case "Documents", "Desktop": return documentColor
            case "Library", "System": return systemColor
            default: return folderColor
            }
        }

        let ext = (name as NSString).pathExtension.lowercased()
        if imageExtensions.contains(ext) { return imageColor }
        if videoExtensions.contains(ext) { return videoColor }
        if audioExtensions.contains(ext) { return audioColor }
        if documentExtensions.contains(ext) { return documentColor }
        if codeExtensions.contains(ext) { return codeColor }
        if archiveExtensions.contains(ext) { return archiveColor }
        return otherColor
    }
}
