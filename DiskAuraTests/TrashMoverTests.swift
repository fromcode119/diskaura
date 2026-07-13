import XCTest
@testable import DiskAura

final class TrashMoverTests: XCTestCase {
    func testMoveTrashesFilesAndReportsFreed() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("dp-tm-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b.txt")
        try "aaaa".write(to: a, atomically: true, encoding: .utf8)
        try "bbbb".write(to: b, atomically: true, encoding: .utf8)

        let outcome = TrashMover.move([(a, 100), (b, 50)])
        XCTAssertEqual(outcome.movedCount, 2)
        XCTAssertEqual(outcome.freedBytes, 150)
        XCTAssertEqual(outcome.failedCount, 0)
        XCTAssertEqual(outcome.restorePairs.count, 2)
        XCTAssertFalse(fm.fileExists(atPath: a.path))

        // Undo path: restore should bring them back to origin.
        let restored = AppUninstallerService.restore(outcome.restorePairs)
        XCTAssertEqual(restored, 2)
        XCTAssertTrue(fm.fileExists(atPath: a.path))
        try? fm.removeItem(at: dir)
    }

    func testMoveCountsMissingItemsAsFailed() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("dp-missing-\(UUID().uuidString).txt")
        let outcome = TrashMover.move([(missing, 10)])
        XCTAssertEqual(outcome.movedCount, 0)
        XCTAssertEqual(outcome.failedCount, 1)
        XCTAssertEqual(outcome.freedBytes, 0)
    }
}
