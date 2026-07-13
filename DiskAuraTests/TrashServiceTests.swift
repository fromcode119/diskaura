import XCTest
@testable import DiskAura

final class TrashServiceTests: XCTestCase {
    func testSizeIsNonNegative() {
        // Real ~/.Trash on the test machine — just assert the call doesn't crash
        // and returns a sane non-negative value.
        XCTAssertGreaterThanOrEqual(TrashService.size(), 0)
    }

    func testItemCountIsNonNegative() {
        XCTAssertGreaterThanOrEqual(TrashService.itemCount(), 0)
    }
}
