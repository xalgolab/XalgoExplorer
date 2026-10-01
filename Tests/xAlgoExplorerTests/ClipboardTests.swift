import AppKit
import XCTest
@testable import xAlgoExplorer

@MainActor
final class ClipboardTests: XCTestCase {
    override func tearDown() {
        NSPasteboard.general.clearContents()
        super.tearDown()
    }

    func testCopySelectionWritesFileURLsToSystemPasteboard() throws {
        let root = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let file = root.appendingPathComponent("sample.txt")
        try Data("copy".utf8).write(to: file)
        let model = ExplorerModel()
        let pane = makePane(directory: root, selected: file)

        model.copySelection(in: pane)

        let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL]
        XCTAssertEqual(urls?.map { ($0 as URL).standardizedFileURL }, [file.standardizedFileURL])
    }

    func testPasteReadsFinderStyleSystemPasteboardFileURLs() async throws {
        let sourceRoot = try makeDirectory()
        let targetRoot = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let file = sourceRoot.appendingPathComponent("finder-copy.txt")
        try Data("finder".utf8).write(to: file)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([file as NSURL])
        let model = ExplorerModel()
        let pane = makePane(directory: targetRoot)

        XCTAssertTrue(model.canPaste(in: pane))
        model.pasteClipboard(in: pane, to: targetRoot)
        await model.waitForPendingFileOperations()

        XCTAssertTrue(FileManager.default.fileExists(atPath: targetRoot.appendingPathComponent("finder-copy.txt").path))
    }

    func testCutPasteBackIntoOriginalDirectoryDoesNotCreateDuplicate() async throws {
        let root = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let file = root.appendingPathComponent("sample.txt")
        try Data("cut".utf8).write(to: file)
        let model = ExplorerModel()
        let pane = makePane(directory: root, selected: file)

        model.cutSelection(in: pane)
        model.pasteClipboard(in: pane, to: root)
        await model.waitForPendingFileOperations()

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("sample 1.txt").path))
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("xAlgoExplorerClipboardTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePane(directory: URL, selected selectedURL: URL? = nil) -> PaneState {
        let pane = PaneState(
            id: .main,
            url: directory,
            viewMode: .list,
            sortField: .name,
            sortAscending: true
        )
        if let selectedURL {
            let entry = FileEntry(
                url: selectedURL,
                name: selectedURL.lastPathComponent,
                isDirectory: false,
                isPackage: false,
                modified: nil,
                created: nil,
                size: 1,
                typeDescription: "text",
                typeIdentifier: nil
            )
            pane.entries = [entry]
            pane.selectedIDs = [entry.id]
        }
        return pane
    }
}
