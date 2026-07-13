import XCTest
@testable import DiskAura

final class ExclusionMatcherTests: XCTestCase {
    func testExactPathExcluded() {
        let m = ExclusionMatcher(paths: ["/Users/x/Work"])
        XCTAssertTrue(m.isExcluded(path: "/Users/x/Work"))
    }

    func testChildPathExcluded() {
        let m = ExclusionMatcher(paths: ["/Users/x/Work"])
        XCTAssertTrue(m.isExcluded(path: "/Users/x/Work/Clients/file.txt"))
    }

    func testSiblingNotExcludedByPrefix() {
        // "/Users/x/Work" must NOT match "/Users/x/Workspace" — that's a prefix but not a child.
        let m = ExclusionMatcher(paths: ["/Users/x/Work"])
        XCTAssertFalse(m.isExcluded(path: "/Users/x/Workspace/file.txt"))
    }

    func testUnrelatedPathNotExcluded() {
        let m = ExclusionMatcher(paths: ["/Users/x/Work"])
        XCTAssertFalse(m.isExcluded(path: "/Users/x/Downloads/a.jpg"))
    }

    func testEmptyListExcludesNothing() {
        let m = ExclusionMatcher(paths: [])
        XCTAssertFalse(m.isExcluded(path: "/anything"))
    }

    func testTrailingSlashNormalized() {
        XCTAssertEqual(ExclusionStore.normalize("/Users/x/Work/"), "/Users/x/Work")
    }
}
