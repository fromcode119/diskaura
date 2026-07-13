import XCTest
@testable import DiskAura

final class MoveServiceTests: XCTestCase {
    private var work: URL!
    private var dest: URL!

    override func setUpWithError() throws {
        let fm = FileManager.default
        work = fm.temporaryDirectory.appendingPathComponent("dp-move-src-\(UUID().uuidString)")
        dest = fm.temporaryDirectory.appendingPathComponent("dp-move-dst-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
        try? FileManager.default.removeItem(at: dest)
    }

    /// Convenience over the current two-step API (plan → move) so the tests read as one call
    /// and assert on the moved-file count.
    @discardableResult
    private func moveNodes(_ nodes: [FileNode], organize: MoveOrganize) throws -> Int {
        let plan = MoveService.plan(nodes, organize: organize)
        return try MoveService.move(plan: plan, to: dest).count
    }

    private func makeFile(_ name: String, modified: Date? = nil) throws -> FileNode {
        let url = work.appendingPathComponent(name)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return FileNode(url: url, isDirectory: false, sizeBytes: 1, modifiedAt: modified)
    }

    func testByTypeSortsIntoCategoryFolders() throws {
        let nodes = [try makeFile("a.png"), try makeFile("b.pdf"), try makeFile("c.zip")]
        let moved = try moveNodes(nodes, organize: .byType)
        XCTAssertEqual(moved, 3)
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("Images/a.png").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("Documents/b.pdf").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("Archives/c.zip").path))
        // Source files are gone (moved, not copied).
        XCTAssertFalse(fm.fileExists(atPath: work.appendingPathComponent("a.png").path))
    }

    func testByDateSortsIntoYearMonthFolders() throws {
        var comps = DateComponents(); comps.year = 2021; comps.month = 3; comps.day = 5
        let date = Calendar.current.date(from: comps)!
        let nodes = [try makeFile("photo.jpg", modified: date)]
        _ = try moveNodes(nodes, organize: .byDate)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("2021-03/photo.jpg").path))
    }

    func testFlatMoveKeepsFilesAtRoot() throws {
        let nodes = [try makeFile("loose.txt")]
        _ = try moveNodes(nodes, organize: .flat)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("loose.txt").path))
    }

    func testCollisionGetsSuffixedNeverOverwrites() throws {
        // Pre-existing file at destination with different content.
        let existing = dest.appendingPathComponent("dup.txt")
        try "ORIGINAL".write(to: existing, atomically: true, encoding: .utf8)
        let nodes = [try makeFile("dup.txt")]
        _ = try moveNodes(nodes, organize: .flat)
        // Original is untouched, the moved one landed as dup-1.txt.
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "ORIGINAL")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("dup-1.txt").path))
    }

    func testSmartOrganizeClustersByMeaningAndMovesEveryFile() throws {
        // Two clear semantic themes plus noise — every file must end up somewhere.
        let names = ["invoice-jan.pdf", "invoice-feb.pdf", "receipt-store.pdf",
                     "vacation-beach.jpg", "vacation-mountain.jpg", "holiday-trip.jpg",
                     "random9281.bin"]
        let nodes = try names.map { try makeFile($0) }
        let groups = SmartOrganizer.groups(for: nodes)
        let placed = groups.reduce(0) { $0 + $1.files.count }
        XCTAssertEqual(placed, nodes.count, "every file must be assigned to some group")

        let moved = try moveNodes(nodes, organize: .smart)
        XCTAssertEqual(moved, nodes.count)
        // All source files left their origin.
        for n in names {
            XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent(n).path))
        }
        // Everything is now under some subfolder of dest (count files recursively).
        let en = FileManager.default.enumerator(at: dest, includingPropertiesForKeys: nil)!
        var fileCount = 0
        for case let u as URL in en where !u.hasDirectoryPath { fileCount += 1 }
        XCTAssertEqual(fileCount, nodes.count)
    }
}
