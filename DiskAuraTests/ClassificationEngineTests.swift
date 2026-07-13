import XCTest
@testable import DiskAura

final class ClassificationEngineTests: XCTestCase {
    func testNodeModulesIsTaggedClean() {
        let engine = ClassificationEngine()
        let url = URL(fileURLWithPath: "/Users/test/project/node_modules")
        XCTAssertEqual(engine.tag(for: url), .clean)
    }

    func testUnknownFolderDefaultsToKeep() {
        let engine = ClassificationEngine()
        let url = URL(fileURLWithPath: "/Users/test/Documents/MyProject")
        XCTAssertEqual(engine.tag(for: url), .keep)
    }
}
