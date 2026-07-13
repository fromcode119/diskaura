import XCTest
@testable import DiskAura

final class FileNodeTests: XCTestCase {
    func testFlattenFilesReturnsOnlyLeaves() {
        let file1 = FileNode(url: URL(fileURLWithPath: "/tmp/a.txt"), isDirectory: false, sizeBytes: 10)
        let file2 = FileNode(url: URL(fileURLWithPath: "/tmp/sub/b.txt"), isDirectory: false, sizeBytes: 20)
        let subdir = FileNode(url: URL(fileURLWithPath: "/tmp/sub"), isDirectory: true, sizeBytes: 20, children: [file2])
        let root = FileNode(url: URL(fileURLWithPath: "/tmp"), isDirectory: true, sizeBytes: 30, children: [file1, subdir])

        let flattened = root.flattenFiles()

        XCTAssertEqual(flattened.count, 2)
        XCTAssertTrue(flattened.contains { $0.path == "/tmp/a.txt" })
        XCTAssertTrue(flattened.contains { $0.path == "/tmp/sub/b.txt" })
    }

    func testSortedChildrenOrdersBySizeDescending() {
        let small = FileNode(url: URL(fileURLWithPath: "/tmp/small"), isDirectory: false, sizeBytes: 5)
        let big = FileNode(url: URL(fileURLWithPath: "/tmp/big"), isDirectory: false, sizeBytes: 500)
        let root = FileNode(url: URL(fileURLWithPath: "/tmp"), isDirectory: true, sizeBytes: 505, children: [small, big])

        XCTAssertEqual(root.sortedChildren.map(\.name), ["big", "small"])
    }
}
