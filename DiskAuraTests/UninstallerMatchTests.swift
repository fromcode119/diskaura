import XCTest
@testable import DiskAura

final class UninstallerMatchTests: XCTestCase {
    private func app(id: String?, name: String) -> InstalledApp {
        InstalledApp(bundlePath: "/Applications/\(name).app", name: name,
                     bundleIdentifier: id, appSizeBytes: 100, lastUsedDate: nil)
    }

    func testZoomYieldsBundleVendorAndName() {
        // Zoom's bundle id is us.zoom.xos — the search must match us.zoom.xos.* files
        // (via the "us.zoom" vendor prefix), the full id, and the name "zoom".
        let needles = Set(AppUninstallerService.matchNeedles(for: app(id: "us.zoom.xos", name: "zoom.us")))
        XCTAssertTrue(needles.contains("us.zoom.xos"))
        XCTAssertTrue(needles.contains("us.zoom"))
        XCTAssertTrue(needles.contains("zoom.us"))
    }

    func testVendorPrefixCatchesRelatedBundles() {
        let needles = AppUninstallerService.matchNeedles(for: app(id: "us.zoom.xos", name: "zoom.us"))
        // A related helper plist "us.zoom.xos.Hotkeys.plist" should be caught by "us.zoom".
        XCTAssertTrue(needles.contains { "us.zoom.xos.hotkeys.plist".contains($0) })
    }

    func testShortNameNotUsedAsNeedle() {
        // A 3-letter name would false-match too much — only bundle-id tokens are used.
        let needles = AppUninstallerService.matchNeedles(for: app(id: "com.acme.pro", name: "Pro"))
        XCTAssertFalse(needles.contains("pro"))
        XCTAssertTrue(needles.contains("com.acme"))
    }

    func testNameFallbackWhenNoBundleID() {
        let needles = AppUninstallerService.matchNeedles(for: app(id: nil, name: "Sketch"))
        XCTAssertTrue(needles.contains("sketch"))
    }

    func testRestoreMovesItemBackToOrigin() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let origin = tmp.appendingPathComponent("dp-restore-\(UUID().uuidString).txt")
        let stash = tmp.appendingPathComponent("dp-stash-\(UUID().uuidString).txt")
        try "hello".write(to: origin, atomically: true, encoding: .utf8)
        try fm.moveItem(at: origin, to: stash)                       // simulate "in Trash"
        XCTAssertFalse(fm.fileExists(atPath: origin.path))

        let restored = AppUninstallerService.restore([.init(original: origin, trashed: stash)])
        XCTAssertEqual(restored, 1)
        XCTAssertTrue(fm.fileExists(atPath: origin.path))
        try? fm.removeItem(at: origin)
    }

    func testRestoreSkipsWhenOriginAlreadyExists() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let origin = tmp.appendingPathComponent("dp-exists-\(UUID().uuidString).txt")
        let stash = tmp.appendingPathComponent("dp-stash2-\(UUID().uuidString).txt")
        try "a".write(to: origin, atomically: true, encoding: .utf8)
        try "b".write(to: stash, atomically: true, encoding: .utf8)

        // Origin already occupied — restore must not clobber it.
        let restored = AppUninstallerService.restore([.init(original: origin, trashed: stash)])
        XCTAssertEqual(restored, 0)
        XCTAssertTrue(fm.fileExists(atPath: stash.path))
        try? fm.removeItem(at: origin); try? fm.removeItem(at: stash)
    }
}
