import AppKit
import XCTest
@testable import xAlgoExplorer

@MainActor
final class DirectoryLoadingTests: XCTestCase {
    func testLatestNavigationWinsAndOtherPanesKeepTheirLocation() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data().write(to: first.appendingPathComponent("old.txt"))
        try Data().write(to: second.appendingPathComponent("new.txt"))
        let model = ExplorerModel()
        await model.waitForPendingReloads()
        let otherURL = model.assistTopPane.url

        model.navigate(model.mainPane, to: first)
        model.navigate(model.mainPane, to: second)
        await model.waitForPendingReloads()

        XCTAssertEqual(model.mainPane.entries.map(\.name), ["new.txt"])
        XCTAssertEqual(model.mainPane.url, second)
        XCTAssertEqual(model.assistTopPane.url, otherURL)
        XCTAssertFalse(model.mainPane.isLoading)
        XCTAssertTrue(model.mainPane.canGoBack)
    }

    func testSortingUsesLoadedContentsAndPreservesSelection() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("a.txt"))
        try Data().write(to: root.appendingPathComponent("z.txt"))
        let model = ExplorerModel()
        model.mainPane.sortField = .name
        model.mainPane.sortAscending = true
        model.navigate(model.mainPane, to: root)
        await model.waitForPendingReloads()
        model.mainPane.selectedIDs = [root.appendingPathComponent("a.txt").path]
        try Data().write(to: root.appendingPathComponent("not-yet-refreshed.txt"))

        model.setSortField(.name, pane: model.mainPane)

        XCTAssertEqual(model.mainPane.entries.map(\.name), ["z.txt", "a.txt"])
        XCTAssertEqual(model.mainPane.selectedIDs, [root.appendingPathComponent("a.txt").path])
        XCTAssertFalse(model.mainPane.isLoading)
    }

    func testFailedDirectoryLoadFinishesWithAnError() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ExplorerModel()
        model.navigate(model.mainPane, to: root.appendingPathComponent("missing"))
        await model.waitForPendingReloads()
        XCTAssertFalse(model.mainPane.isLoading)
        XCTAssertNotNil(model.mainPane.errorMessage)
        XCTAssertTrue(model.mainPane.entries.isEmpty)
    }

    func testBackgroundCutDoesNotEraseNewerClipboardContents() async throws {
        let root = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            NSPasteboard.general.clearContents()
        }
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("sample.txt")
        try Data("original".utf8).write(to: file)
        let model = ExplorerModel()
        model.navigate(model.mainPane, to: root)
        await model.waitForPendingReloads()
        let entry = try XCTUnwrap(model.mainPane.entries.first { $0.name == "sample.txt" })
        model.mainPane.selectedIDs = [entry.id]
        model.cutSelection(in: model.mainPane)
        XCTAssertNotNil(model.clipboard)

        model.pasteClipboard(in: model.mainPane, to: destination)
        XCTAssertTrue(model.isPerformingFileOperation)
        XCTAssertFalse(model.canPaste(in: model.mainPane))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("newer content", forType: .string)
        await model.waitForPendingFileOperations()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "newer content")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("sample.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(model.isPerformingFileOperation)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xAlgoNativeTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
