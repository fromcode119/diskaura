import XCTest
@testable import DiskAura

final class VolumeInfoServiceTests: XCTestCase {
    func testRealVolumeReturnsConsistentStats() throws {
        let stats = try XCTUnwrap(VolumeInfoService.stats(for: FileManager.default.homeDirectoryForCurrentUser))
        XCTAssertGreaterThan(stats.totalBytes, 0)
        XCTAssertGreaterThanOrEqual(stats.freeBytes, 0)
        XCTAssertLessThanOrEqual(stats.freeBytes, stats.totalBytes)
        // used must be exactly total - strict free (the invariant the headline number relies on).
        XCTAssertEqual(stats.usedBytes, stats.totalBytes - stats.freeBytes)
        XCTAssertGreaterThanOrEqual(stats.purgeableHint, 0)
    }
}
