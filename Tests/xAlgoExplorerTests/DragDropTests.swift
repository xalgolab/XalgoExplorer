import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import xAlgoExplorer

@MainActor
final class DragDropTests: XCTestCase {
    func testDropOperationMatchesFinderStyleDefaultsAndOverrides() {
        let source = URL(fileURLWithPath: "/Volumes/A/1.txt")
        let target = URL(fileURLWithPath: "/Volumes/B")

        XCTAssertEqual(
            ExplorerModel.preferredDropOperation(
                sourceURLs: [source],
                into: target,
                intent: .automatic,
                sameVolume: { _, _ in true }
            ),
            .move
        )
        XCTAssertEqual(
            ExplorerModel.preferredDropOperation(
                sourceURLs: [source],
                into: target,
                intent: .automatic,
                sameVolume: { _, _ in false }
            ),
            .copy
        )
        XCTAssertEqual(
            ExplorerModel.preferredDropOperation(
                sourceURLs: [source],
                into: target,
                intent: .forceCopy,
                sameVolume: { _, _ in true }
            ),
            .copy
        )
        XCTAssertEqual(
            ExplorerModel.preferredDropOperation(
                sourceURLs: [source],
                into: target,
                intent: .forceMove,
                sameVolume: { _, _ in false }
            ),
            .move
        )
    }

    func testInternalFileDropMovesItemIntoTargetDirectory() async throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("xAlgoExplorerDragDropTests-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let file = source.appendingPathComponent("sample.txt")
        try Data("drag test".utf8).write(to: file)

        let payload = InternalFileDragPayload(sourcePaneID: .main, paths: [file.path])
        let data = try JSONEncoder().encode(payload)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.xAlgoInternalFileDrag.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(data, nil)
            return nil
        }

        let model = ExplorerModel()
        XCTAssertTrue(model.handleDrop([provider], into: target))

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("sample.txt").path))
    }

    func testAppKitPasteboardDragWritesInternalPayloadAndFileURL() throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("xAlgoExplorerDragDropTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let file = root.appendingPathComponent("sample.txt")
        try Data("drag test".utf8).write(to: file)

        let model = ExplorerModel()
        let item = dragPasteboardItem(for: file, in: root, model: model)

        XCTAssertEqual(item.string(forType: .fileURL), file.absoluteString)
        XCTAssertNotNil(item.data(forType: NSPasteboard.PasteboardType(UTType.xAlgoInternalFileDrag.identifier)))
    }

    func testAppKitMultiItemPasteboardDragWritesEachFileURL() throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("xAlgoExplorerDragDropTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let first = root.appendingPathComponent("first.txt")
        let second = root.appendingPathComponent("second.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let model = ExplorerModel()
        let pane = PaneState(id: .main, url: root, viewMode: .list, sortField: .name, sortAscending: true)
        pane.entries = [first, second].map { url in
            FileEntry(
                url: url,
                name: url.lastPathComponent,
                isDirectory: false,
                isPackage: false,
                modified: nil,
                created: nil,
                size: 5,
                typeDescription: "text",
                typeIdentifier: nil
            )
        }
        pane.selectedIDs = Set(pane.entries.map(\.id))

        let firstItem = model.dragPasteboardItem(for: pane.entries[0], in: pane)
        let secondItem = model.dragPasteboardItem(for: pane.entries[1], in: pane)

        XCTAssertEqual(firstItem.string(forType: .fileURL), first.absoluteString)
        XCTAssertEqual(secondItem.string(forType: .fileURL), second.absoluteString)
    }

    func testAppKitPasteboardInternalDropMovesItemIntoTargetDirectory() async throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("xAlgoExplorerDragDropTests-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let file = source.appendingPathComponent("sample.txt")
        try Data("drag test".utf8).write(to: file)

        let model = ExplorerModel()
        let item = dragPasteboardItem(for: file, in: source, model: model)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("xAlgoExplorerDragDropTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([item]))

        XCTAssertEqual(model.dropOperation(from: pasteboard, into: target, intent: .automatic), .move)
        XCTAssertTrue(model.handleDrop(from: pasteboard, into: target))
        await model.waitForPendingFileOperations()

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("sample.txt").path))
    }

    func testForceCopyInsideSameDirectoryCreatesDuplicate() async throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("xAlgoExplorerDragDropTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let file = root.appendingPathComponent("sample.txt")
        try Data("drag test".utf8).write(to: file)

        let model = ExplorerModel()
        let provider = dragProvider(for: file, in: root, model: model)

        XCTAssertTrue(model.handleDrop([provider], into: root, intent: .forceCopy))

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let copiedFiles = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("sample") && $0.hasSuffix(".txt") }
        XCTAssertEqual(copiedFiles.count, 2)
    }

    func testForceCopyBetweenDirectoriesKeepsOriginal() async throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("xAlgoExplorerDragDropTests-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let file = source.appendingPathComponent("sample.txt")
        try Data("drag test".utf8).write(to: file)

        let model = ExplorerModel()
        let provider = dragProvider(for: file, in: source, model: model)

        XCTAssertTrue(model.handleDrop([provider], into: target, intent: .forceCopy))

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("sample.txt").path))
    }

    func testInternalFileDropBackIntoSourceDirectoryIsRejected() async throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("xAlgoExplorerDragDropTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let file = root.appendingPathComponent("sample.txt")
        try Data("drag test".utf8).write(to: file)

        let model = ExplorerModel()
        let provider = dragProvider(for: file, in: root, model: model)

        XCTAssertFalse(model.canDropActiveInternalDrag(into: root))
        XCTAssertFalse(model.handleDrop([provider], into: root))

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("sample 1.txt").path))
    }

    func testCancelledInternalDragDoesNotHijackLaterFileURLDrop() async throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("xAlgoExplorerDragDropTests-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        let external = root.appendingPathComponent("external")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let cancelledFile = source.appendingPathComponent("cancelled.txt")
        let laterFile = external.appendingPathComponent("later.txt")
        try Data("cancelled".utf8).write(to: cancelledFile)
        try Data("later".utf8).write(to: laterFile)

        let model = ExplorerModel()
        _ = dragProvider(for: cancelledFile, in: source, model: model)
        let fileURLOnlyProvider = NSItemProvider(item: laterFile as NSURL, typeIdentifier: UTType.fileURL.identifier)

        XCTAssertTrue(model.handleDrop([fileURLOnlyProvider], into: target))

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cancelledFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("cancelled.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: laterFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("later.txt").path))
    }

    func testDirectoryCannotBeDroppedIntoItselfOrDescendant() throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("xAlgoExplorerDragDropTests-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("folder")
        let child = folder.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let model = ExplorerModel()
        _ = dragProvider(for: folder, in: root, model: model, isDirectory: true)

        XCTAssertFalse(model.canDropActiveInternalDrag(into: folder))
        XCTAssertFalse(model.canDropActiveInternalDrag(into: child))
    }

    func testExternalPasteboardCannotReuseCachedInternalDrag() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stale = source.appendingPathComponent("cancelled.txt")
        let current = source.appendingPathComponent("current.txt")
        try Data("stale".utf8).write(to: stale)
        try Data("current".utf8).write(to: current)
        let model = ExplorerModel()
        _ = dragPasteboardItem(for: stale, in: source, model: model)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([current as NSURL])

        XCTAssertTrue(model.handleDrop(from: pasteboard, into: target))
        await model.waitForPendingFileOperations()

        XCTAssertTrue(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("current.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("cancelled.txt").path))
    }

    func testExternalPasteboardDropIntoOriginalDirectoryIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sample.txt")
        try Data("test".utf8).write(to: file)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([file as NSURL])
        let model = ExplorerModel()
        XCTAssertFalse(model.handleDrop(from: pasteboard, into: root))
        XCTAssertFalse(model.isPerformingFileOperation)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["sample.txt"])
    }

    func testDroppedDirectoryCanNavigateTargetPaneWithoutMovingIt() throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("xAlgoExplorerDragDropTests-\(UUID().uuidString)")
        let sourceRoot = root.appendingPathComponent("source")
        let targetRoot = root.appendingPathComponent("target")
        let folder = sourceRoot.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let model = ExplorerModel()
        let provider = dragProvider(for: folder, in: sourceRoot, model: model, isDirectory: true)
        let targetPane = PaneState(
            id: .assistTop,
            url: targetRoot,
            viewMode: .list,
            sortField: .name,
            sortAscending: true
        )

        XCTAssertTrue(model.navigateToDroppedDirectory([provider], in: targetPane))

        XCTAssertEqual(targetPane.url.standardizedFileURL, folder.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetRoot.appendingPathComponent("folder").path))
    }

    private func dragProvider(
        for url: URL,
        in directory: URL,
        model: ExplorerModel,
        isDirectory: Bool = false
    ) -> NSItemProvider {
        let pane = PaneState(
            id: .main,
            url: directory,
            viewMode: .list,
            sortField: .name,
            sortAscending: true
        )
        let entry = FileEntry(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            isPackage: false,
            modified: nil,
            created: nil,
            size: isDirectory ? nil : 9,
            typeDescription: isDirectory ? "folder" : "text",
            typeIdentifier: nil
        )
        pane.entries = [entry]
        return model.dragProvider(for: entry, in: pane)
    }

    private func dragPasteboardItem(
        for url: URL,
        in directory: URL,
        model: ExplorerModel,
        isDirectory: Bool = false
    ) -> NSPasteboardItem {
        let pane = PaneState(
            id: .main,
            url: directory,
            viewMode: .list,
            sortField: .name,
            sortAscending: true
        )
        let entry = FileEntry(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            isPackage: false,
            modified: nil,
            created: nil,
            size: isDirectory ? nil : 9,
            typeDescription: isDirectory ? "folder" : "text",
            typeIdentifier: nil
        )
        pane.entries = [entry]
        return model.dragPasteboardItem(for: entry, in: pane)
    }
}
