import Foundation

/// One Homebrew package — installed or available in the catalog.
struct BrewPackage: Identifiable, Equatable {
    enum Kind: String { case formula, cask }

    let name: String
    let kind: Kind
    /// Installed version, empty when the package is only a catalog result.
    var installedVersion: String = ""
    /// Latest version brew knows about.
    var latestVersion: String = ""
    var desc: String = ""
    var homepage: String = ""
    var isOutdated: Bool = false
    var isInstalled: Bool { !installedVersion.isEmpty }
    /// On-disk size of the package's Cellar/Caskroom directory; 0 when unknown.
    var sizeBytes: Int64 = 0

    var id: String { "\(kind.rawValue):\(name)" }
}
