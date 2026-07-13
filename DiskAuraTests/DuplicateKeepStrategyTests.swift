import XCTest
@testable import DiskAura

final class DuplicateKeepStrategyTests: XCTestCase {
    private func file(_ path: String, _ daysAgo: Double) -> DuplicateFile {
        DuplicateFile(url: URL(fileURLWithPath: path), sizeBytes: 1000,
                      modifiedAt: Date().addingTimeInterval(-daysAgo * 86_400))
    }

    func testSmartPrefersRealLocationOverJunk() {
        let group = DuplicateGroup(files: [
            file("/Users/x/Downloads/photo.jpg", 1),          // junk location, newer
            file("/Users/x/Pictures/2024/photo.jpg", 30),     // real location, older
        ])
        XCTAssertEqual(group.keeper(.smart)?.url.path, "/Users/x/Pictures/2024/photo.jpg",
                       "Smart should keep the organized copy even if it's older")
    }

    func testSmartFallsBackToNewestWhenBothJunk() {
        // Both under /tmp (junk) — the exact case the stress test surfaced. Newer should win.
        let group = DuplicateGroup(files: [
            file("/private/tmp/dp/Downloads/photo.jpg", 5),       // older
            file("/private/tmp/dp/Documents/keep/photo.jpg", 1),  // newer
        ])
        XCTAssertEqual(group.keeper(.smart)?.url.path, "/private/tmp/dp/Documents/keep/photo.jpg")
    }

    func testNewestAndOldest() {
        let group = DuplicateGroup(files: [
            file("/a/photo.jpg", 10),
            file("/b/photo.jpg", 2),
            file("/c/photo.jpg", 40),
        ])
        XCTAssertEqual(group.keeper(.newest)?.url.path, "/b/photo.jpg")
        XCTAssertEqual(group.keeper(.oldest)?.url.path, "/c/photo.jpg")
    }
}
