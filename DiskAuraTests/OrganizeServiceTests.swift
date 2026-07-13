import XCTest
@testable import DiskAura

final class OrganizeServiceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("dp-org-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func make(_ name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testByTypeOrganizesInPlaceOneLevel() throws {
        _ = try make("a.png"); _ = try make("b.pdf")
        let plan = OrganizeService.plan(for: dir, scheme: .byType)
        _ = try OrganizeService.organize(plan, in: dir)
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("Images/a.png").path))
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("Documents/b.pdf").path))
    }

    func testByTypeThenTopicProducesNestedTree() throws {
        _ = try make("invoice-january.pdf"); _ = try make("invoice-february.pdf")
        let plan = OrganizeService.plan(for: dir, scheme: .byTypeThenTopic)
        // Nested: every planned item has 2 path components (type / topic).
        XCTAssertTrue(plan.allSatisfy { $0.folderComponents.count == 2 })
        XCTAssertTrue(plan.allSatisfy { $0.folderComponents.first == "Documents" })
        let result = try OrganizeService.organize(plan, in: dir)
        XCTAssertEqual(result.movedCount, 2)
        let fm = FileManager.default
        // A "Documents" folder exists with a topic subfolder inside it (nested, not flat).
        let documents = dir.appendingPathComponent("Documents")
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: documents.path, isDirectory: &isDir) && isDir.boolValue)
        let subEntries = try fm.contentsOfDirectory(at: documents, includingPropertiesForKeys: [.isDirectoryKey])
        let subDirs = subEntries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        XCTAssertFalse(subDirs.isEmpty, "expected a topic subfolder nested under Documents")
        // Neither invoice remains loose at the top level.
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("invoice-january.pdf").path))
    }

    func testExistingSubfoldersAreLeftUntouched() throws {
        let sub = dir.appendingPathComponent("KeepMe")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "y".write(to: sub.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)
        _ = try make("loose.png")
        let plan = OrganizeService.plan(for: dir, scheme: .byType)
        // Only the loose file is planned, not the file inside the existing subfolder.
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.file.lastPathComponent, "loose.png")
        _ = try OrganizeService.organize(plan, in: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sub.appendingPathComponent("inside.txt").path))
    }
}
