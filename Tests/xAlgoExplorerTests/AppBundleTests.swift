import XCTest
@testable import xAlgoExplorer

final class AppBundleTests: XCTestCase {
    func testAppIconAssetExistsAndPackagingReferencesIt() throws {
        let root = repositoryRoot()
        let iconURL = root
            .appendingPathComponent("Sources/xAlgoExplorer/Resources/AppIcon.icns")
        let packageScript = try String(
            contentsOf: root.appendingPathComponent("scripts/package-app.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))
        XCTAssertTrue(packageScript.contains("CFBundleIconFile"))
        XCTAssertTrue(packageScript.contains("AppIcon"))
    }

    func testAppPackagingScriptSignsBundleForCandidateBuilds() throws {
        let root = repositoryRoot()
        let packageScript = try String(
            contentsOf: root.appendingPathComponent("scripts/package-app.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(packageScript.contains("codesign --force --deep --sign -"))
    }

    func testDmgPackagingScriptCreatesApplicationInstallerImage() throws {
        let root = repositoryRoot()
        let packageScript = try String(
            contentsOf: root.appendingPathComponent("scripts/package-dmg.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(packageScript.contains("dist/xAlgo Explorer.app"))
        XCTAssertTrue(packageScript.contains("/Applications"))
        XCTAssertTrue(packageScript.contains("hdiutil create"))
        XCTAssertTrue(packageScript.contains("shasum -a 256"))
    }

    func testAboutMetadataContainsRequiredCopyright() {
        XCTAssertEqual(AppMetadata.copyright, "Copyright by 8G 2026 xAlgo Inc.")
    }

    func testCandidateVersionMetadataIsSynchronizedWithPackagingScripts() throws {
        let root = repositoryRoot()
        let appScript = try String(
            contentsOf: root.appendingPathComponent("scripts/package-app.sh"),
            encoding: .utf8
        )
        let dmgScript = try String(
            contentsOf: root.appendingPathComponent("scripts/package-dmg.sh"),
            encoding: .utf8
        )

        XCTAssertEqual(AppMetadata.version, "v0.2.0-candidate")
        XCTAssertTrue(appScript.contains("<string>v0.2.0-candidate</string>"))
        XCTAssertTrue(appScript.contains("<string>3</string>"))
        XCTAssertTrue(dmgScript.contains("VERSION=\"v0.2.0-candidate\""))
        XCTAssertTrue(dmgScript.contains("xAlgo_Explorer_${VERSION}_${ARCH_NAME}.dmg"))
    }

    func testCandidateChangelogContainsMultilingualReleaseNotes() throws {
        let changelog = try String(
            contentsOf: repositoryRoot().appendingPathComponent("CHANGELOG.md"),
            encoding: .utf8
        )

        for marker in [
            "## v0.2.0-candidate - 2026-10-01",
            "## v0.1.2-candidate - 2026-05-08",
            "### 简体中文",
            "### 繁體中文",
            "### English",
            "### 日本語",
            "### 한국어",
            "### Français",
            "### Deutsch",
            "### Español",
            "### Português",
            "### Русский"
        ] {
            XCTAssertTrue(changelog.contains(marker), "Missing changelog marker: \(marker)")
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
