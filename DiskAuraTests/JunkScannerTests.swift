import XCTest
@testable import DiskAura

final class JunkScannerTests: XCTestCase {
    func testCategoryTotalsSumItems() {
        let cat = JunkCategory(
            id: "x", title: "Caches", icon: "shippingbox", explanation: "",
            items: [
                JunkItem(url: URL(fileURLWithPath: "/a"), sizeBytes: 100),
                JunkItem(url: URL(fileURLWithPath: "/b"), sizeBytes: 250),
            ],
            recommended: true
        )
        XCTAssertEqual(cat.totalBytes, 350)
        XCTAssertFalse(cat.isEmpty)
    }

    func testEmptyCategoryIsEmpty() {
        let cat = JunkCategory(id: "x", title: "Logs", icon: "doc", explanation: "", items: [], recommended: true)
        XCTAssertTrue(cat.isEmpty)
        XCTAssertEqual(cat.totalBytes, 0)
    }

    func testScanIsCancellableImmediately() {
        // A cancelled scan should return nothing rather than walking the whole Library.
        let result = JunkScanner.scan(isCancelled: { true })
        XCTAssertTrue(result.isEmpty)
    }

    func testJunkItemNameIsLastComponent() {
        let item = JunkItem(url: URL(fileURLWithPath: "/Users/x/Library/Caches/com.apple.Safari"), sizeBytes: 10)
        XCTAssertEqual(item.name, "com.apple.Safari")
    }
}
