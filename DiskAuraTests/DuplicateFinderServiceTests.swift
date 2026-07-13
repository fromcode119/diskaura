import XCTest
@testable import DiskAura

final class DuplicateFinderServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testFindsIdenticalFilesAsDuplicates() async {
        let content = Data(repeating: 0x42, count: 4096)
        let fileA = tempDir.appendingPathComponent("a.bin")
        let fileB = tempDir.appendingPathComponent("subdir/b.bin")
        try? FileManager.default.createDirectory(at: fileB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: fileA)
        try? content.write(to: fileB)

        let groups = await DuplicateFinderService.findDuplicates(in: tempDir, minSizeBytes: 10)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.count, 2)
    }

    func testDifferentContentIsNotADuplicate() async {
        let fileA = tempDir.appendingPathComponent("a.bin")
        let fileB = tempDir.appendingPathComponent("b.bin")
        try? Data(repeating: 0x01, count: 4096).write(to: fileA)
        try? Data(repeating: 0x02, count: 4096).write(to: fileB)

        let groups = await DuplicateFinderService.findDuplicates(in: tempDir, minSizeBytes: 10)

        XCTAssertTrue(groups.isEmpty)
    }

    func testFilesBelowMinSizeAreIgnored() async {
        let content = Data(repeating: 0x42, count: 10)
        let fileA = tempDir.appendingPathComponent("a.bin")
        let fileB = tempDir.appendingPathComponent("b.bin")
        try? content.write(to: fileA)
        try? content.write(to: fileB)

        let groups = await DuplicateFinderService.findDuplicates(in: tempDir, minSizeBytes: 1024)

        XCTAssertTrue(groups.isEmpty)
    }
}
