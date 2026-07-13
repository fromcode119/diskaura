import XCTest
@testable import DiskAura

final class CleanupSafetyTests: XCTestCase {
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    func testAllowsUserCachesAndLogs() {
        XCTAssertTrue(CleanupSafety.isSafeToClean(home.appendingPathComponent("Library/Caches/com.some.App")))
        XCTAssertTrue(CleanupSafety.isSafeToClean(home.appendingPathComponent("Library/Logs/some.log")))
        XCTAssertTrue(CleanupSafety.isSafeToClean(home.appendingPathComponent(".gradle/caches/modules")))
        XCTAssertTrue(CleanupSafety.isSafeToClean(home.appendingPathComponent("Downloads/installer.dmg")))
    }

    func testBlocksSystemTrees() {
        XCTAssertFalse(CleanupSafety.isSafeToClean(URL(fileURLWithPath: "/System/Library/Caches/x")))
        XCTAssertFalse(CleanupSafety.isSafeToClean(URL(fileURLWithPath: "/Library/Caches/x")))
        XCTAssertFalse(CleanupSafety.isSafeToClean(URL(fileURLWithPath: "/usr/local/bin")))
        XCTAssertFalse(CleanupSafety.isSafeToClean(URL(fileURLWithPath: "/Applications/Mail.app")))
    }

    func testBlocksProtectedHomeFoldersThemselves() {
        // The folders themselves are protected; their cache contents are not.
        XCTAssertFalse(CleanupSafety.isSafeToClean(home.appendingPathComponent("Library")))
        XCTAssertFalse(CleanupSafety.isSafeToClean(home.appendingPathComponent("Documents")))
        XCTAssertFalse(CleanupSafety.isSafeToClean(home.appendingPathComponent("Desktop")))
        XCTAssertFalse(CleanupSafety.isSafeToClean(home)) // home itself
    }

    func testBlocksAnythingOutsideHome() {
        XCTAssertFalse(CleanupSafety.isSafeToClean(URL(fileURLWithPath: "/tmp/whatever")))
        XCTAssertFalse(CleanupSafety.isSafeToClean(URL(fileURLWithPath: "/private/var/db/receipts")))
    }
}
