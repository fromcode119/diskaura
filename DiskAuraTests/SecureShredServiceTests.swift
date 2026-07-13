import XCTest
@testable import DiskAura

final class SecureShredServiceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("dp-shred-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testShredRemovesFileAndReportsSize() async throws {
        let file = dir.appendingPathComponent("secret.txt")
        let payload = String(repeating: "TOP-SECRET-", count: 500)  // ~5.5 KB
        try payload.write(to: file, atomically: true, encoding: .utf8)
        let expected = Int64((try Data(contentsOf: file)).count)

        let outcome = await SecureShredService.shred([file], passes: 3)

        guard case let .done(files, bytes) = outcome else {
            return XCTFail("expected .done, got \(outcome)")
        }
        XCTAssertEqual(files, 1)
        XCTAssertEqual(bytes, expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "file must be gone after shredding")
    }

    func testShredFolderRemovesEveryFileAndTheFolder() async throws {
        let sub = dir.appendingPathComponent("box")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for n in ["a.txt", "b.bin", "c.log"] {
            try "x".write(to: sub.appendingPathComponent(n), atomically: true, encoding: .utf8)
        }
        let outcome = await SecureShredService.shred([sub], passes: 1)
        guard case let .done(files, _) = outcome else { return XCTFail("expected .done, got \(outcome)") }
        XCTAssertEqual(files, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sub.path))
    }

    func testRefusesProtectedSystemPath() async throws {
        let outcome = await SecureShredService.shred([URL(fileURLWithPath: "/System/Library")], passes: 1)
        guard case .failed = outcome else { return XCTFail("expected .failed for a system path, got \(outcome)") }
    }

    func testEmptyFileIsHandled() async throws {
        let file = dir.appendingPathComponent("empty.dat")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        let outcome = await SecureShredService.shred([file], passes: 1)
        guard case let .done(files, bytes) = outcome else { return XCTFail("expected .done") }
        XCTAssertEqual(files, 1)
        XCTAssertEqual(bytes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
