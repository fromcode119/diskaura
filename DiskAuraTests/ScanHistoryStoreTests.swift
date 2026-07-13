import XCTest
@testable import DiskAura

final class ScanHistoryStoreTests: XCTestCase {
    private func makeResult(rootPath: String, totalSize: Int64, childSizes: [String: Int64]) -> ScanResult {
        let root = FileNode(
            url: URL(fileURLWithPath: rootPath),
            isDirectory: true,
            sizeBytes: totalSize,
            children: childSizes.map { name, size in
                FileNode(url: URL(fileURLWithPath: rootPath).appendingPathComponent(name), isDirectory: true, sizeBytes: size)
            }
        )
        return ScanResult(root: root, scannedAt: Date(), volume: nil, skippedPaths: [], deniedPaths: [])
    }

    func testDeltasReflectGrowthAndShrinkage() {
        let store = ScanHistoryStore()
        let rootPath = "/tmp/diskaura-history-test-\(UUID().uuidString)"

        store.record(makeResult(rootPath: rootPath, totalSize: 100, childSizes: ["a": 60, "b": 40]))
        store.record(makeResult(rootPath: rootPath, totalSize: 150, childSizes: ["a": 90, "b": 40, "c": 20]))

        let deltas = store.deltas(for: rootPath)
        let aDelta = deltas.first { $0.name == "a" }
        let cDelta = deltas.first { $0.name == "c" }

        XCTAssertEqual(aDelta?.deltaBytes, 30)
        XCTAssertEqual(cDelta?.deltaBytes, 20)
        XCTAssertNil(deltas.first { $0.name == "b" }) // unchanged, filtered out
    }

    func testLatestReturnsMostRecentSnapshot() {
        let store = ScanHistoryStore()
        let rootPath = "/tmp/diskaura-history-test-\(UUID().uuidString)"

        store.record(makeResult(rootPath: rootPath, totalSize: 100, childSizes: [:]))
        store.record(makeResult(rootPath: rootPath, totalSize: 200, childSizes: [:]))

        XCTAssertEqual(store.latest(for: rootPath)?.totalBytes, 200)
    }
}
