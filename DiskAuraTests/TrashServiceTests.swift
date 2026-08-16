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

@MainActor
extension TrashServiceTests {
    /// The disk figure is what the user cares about — a Trash that emptied 30GB while the volume
    /// only got 2GB back must SAY so, not claim 30GB was reclaimed. This is the exact case that
    /// made cleaning look like it was lying.
    func testSnapshotHeldShortfallIsReportedHonestly() {
        let out = TrashService.EmptyOutcome(bytesRemovedFromTrash: 30_000_000_000,
                                            bytesReclaimedOnDisk: 2_000_000_000,
                                            heldBySnapshots: true)
        let msg = CleanupViewModel.emptyOutcomeMessage(out)
        XCTAssertTrue(msg.contains("snapshot"), "must explain WHY the space didn't come back: \(msg)")
        XCTAssertFalse(msg.contains("reclaimed 30"), "must not claim the full amount was reclaimed")
    }

    /// Normal case: report the measured disk delta, not the intended size.
    func testNormalEmptyReportsDiskFigure() {
        let out = TrashService.EmptyOutcome(bytesRemovedFromTrash: 5_000_000_000,
                                            bytesReclaimedOnDisk: 5_000_000_000,
                                            heldBySnapshots: false)
        XCTAssertTrue(CleanupViewModel.emptyOutcomeMessage(out).contains("reclaimed"))
    }

    func testEmptyTrashWhenAlreadyEmpty() {
        let out = TrashService.EmptyOutcome(bytesRemovedFromTrash: 0, bytesReclaimedOnDisk: 0, heldBySnapshots: false)
        XCTAssertTrue(CleanupViewModel.emptyOutcomeMessage(out).contains("already empty"))
    }
}
