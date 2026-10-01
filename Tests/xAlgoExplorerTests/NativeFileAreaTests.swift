import AppKit
import Combine
import XCTest
@testable import xAlgoExplorer

@MainActor
final class NativeFileAreaTests: XCTestCase {
    func testUnchangedEntriesDoNotRequestAnyRefresh() {
        let entries = makeEntries()
        let changes = AppKitFileAreaChanges(previous: entries, next: entries)

        XCTAssertFalse(changes.requiresReload)
        XCTAssertTrue(changes.changedIndexes.isEmpty)
    }

    func testMetadataChangeOnlyRefreshesAffectedItem() {
        let entries = makeEntries()
        var next = entries
        next[1] = makeEntry("b.txt", size: 42, typeDescription: "updated type")
        let changes = AppKitFileAreaChanges(previous: entries, next: next)

        XCTAssertFalse(changes.requiresReload)
        XCTAssertEqual(changes.changedIndexes, IndexSet(integer: 1))
    }

    func testReorderInsertionAndRemovalRequireStructuralReload() {
        let entries = makeEntries()
        for next in [Array(entries.reversed()), entries + [makeEntry("d.txt")], Array(entries.dropLast())] {
            XCTAssertTrue(AppKitFileAreaChanges(previous: entries, next: next).requiresReload)
        }
    }

    func testDeselectedCursorDoesNotScrollAwayFromSelection() {
        let entries = makeEntries()
        XCTAssertEqual(AppKitSelectionScrollTarget.tableRow(
            entries: entries, selectedIDs: [entries[0].id], cursorID: entries[2].id
        ), 0)
        XCTAssertNil(AppKitSelectionScrollTarget.collectionIndexPath(
            entries: entries, selectedIDs: [], cursorID: entries[2].id
        ))
    }

    func testSelectionSnapshotDetectsCursorMovementWithinSameSelection() {
        let pane = makePane()
        pane.selectedIDs = Set(pane.entries.map(\.id))
        pane.selectionCursorID = pane.entries[0].id
        let first = AppKitFileAreaSelection(pane: pane)
        pane.selectionCursorID = pane.entries[2].id

        XCTAssertNotEqual(first, AppKitFileAreaSelection(pane: pane))
    }

    func testShiftSelectionPreservesExistingAnchor() {
        XCTAssertEqual(AppKitNativeSelection.anchor(
            previous: "b", cursor: "a", selectedIDs: ["a", "b", "c"], extending: true
        ), "b")
        XCTAssertEqual(AppKitNativeSelection.anchor(
            previous: "b", cursor: "a", selectedIDs: ["a"], extending: false
        ), "a")
        XCTAssertNil(AppKitNativeSelection.anchor(
            previous: "b", cursor: "a", selectedIDs: [], extending: true
        ))
    }

    func testMarqueeModifiersUseInitialSelectionRatherThanAccumulatingHits() {
        let initial = IndexSet([1, 3])
        XCTAssertEqual(AppKitNativeSelection.marqueeSelection(
            initial: initial, intersecting: IndexSet([2, 3]), modifiers: []
        ), IndexSet([2, 3]))
        XCTAssertEqual(AppKitNativeSelection.marqueeSelection(
            initial: initial, intersecting: IndexSet([2, 3]), modifiers: .shift
        ), IndexSet([1, 2, 3]))
        XCTAssertEqual(AppKitNativeSelection.marqueeSelection(
            initial: initial, intersecting: IndexSet([2, 3]), modifiers: .command
        ), IndexSet([1, 2]))
        XCTAssertEqual(AppKitNativeSelection.marqueeSelection(
            initial: initial, intersecting: [], modifiers: .command
        ), initial)
    }

    func testNativeArrowRoutingDoesNotConsumeBusinessNavigationShortcuts() throws {
        XCTAssertTrue(AppKitNativeSelection.isNavigationKey(try keyEvent(125)))
        XCTAssertTrue(AppKitNativeSelection.isNavigationKey(try keyEvent(126, modifiers: .shift)))
        XCTAssertFalse(AppKitNativeSelection.isNavigationKey(try keyEvent(123, modifiers: .option)))
        XCTAssertFalse(AppKitNativeSelection.isNavigationKey(try keyEvent(36)))
    }

    func testTableSelectionUpdateKeepsExistingCellAndDoesNotPublishColumnChanges() throws {
        let (model, pane) = makeModelAndPane()
        let controller = AppKitFileTableController()
        controller.configure(model: model, pane: pane, role: .main)
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 420)
        controller.view.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(descendant(of: NSTableView.self, in: controller.view))
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        cell.textField?.stringValue = "selection-must-not-reconfigure-this-cell"
        pane.selectedIDs = [pane.entries[0].id]
        pane.selectionCursorID = pane.entries[0].id
        var publications = 0
        let observation = pane.objectWillChange.sink { publications += 1 }

        controller.configure(model: model, pane: pane, role: .main)

        XCTAssertTrue(table.view(atColumn: 0, row: 0, makeIfNecessary: false) === cell)
        XCTAssertEqual(cell.textField?.stringValue, "selection-must-not-reconfigure-this-cell")
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 0))
        XCTAssertEqual(table.identifier, NativePaneFocus.identifier(for: pane.id))
        withExtendedLifetime(observation) {}
    }

    func testTableColumnsRespectWidePersistedWidthsWithoutWritingBack() throws {
        let (model, pane) = makeModelAndPane()
        pane.setWidth(1_280, for: .name)
        let controller = AppKitFileTableController()
        var publications = 0
        let observation = pane.objectWillChange.sink { publications += 1 }

        controller.configure(model: model, pane: pane, role: .main)

        let table = try XCTUnwrap(descendant(of: NSTableView.self, in: controller.view))
        XCTAssertEqual(table.tableColumns[0].width, 1_280, accuracy: 0.5)
        XCTAssertEqual(publications, 0)
        XCTAssertFalse(table.allowsColumnReordering)
        withExtendedLifetime(observation) {}
    }

    func testNativeTableArrowSelectionRemainsVisible() throws {
        let (model, pane) = makeModelAndPane()
        pane.entries = (0..<100).map { makeEntry(String(format: "%03d.txt", $0)) }
        let controller = AppKitFileTableController()
        controller.configure(model: model, pane: pane, role: .main)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.close() }
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 300)
        controller.view.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(descendant(of: NSTableView.self, in: controller.view))
        let scroll = try XCTUnwrap(table.enclosingScrollView)
        scroll.tile()
        window.makeFirstResponder(table)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "\u{f701}", charactersIgnoringModifiers: "\u{f701}", isARepeat: false, keyCode: 125
        ))
        for _ in 0..<30 {
            table.keyDown(with: event)
            controller.configure(model: model, pane: pane, role: .main)
            controller.view.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(table.selectedRow, 29)
        let rowRect = table.rect(ofRow: table.selectedRow)
        let visible = table.convert(scroll.contentView.bounds, from: scroll.contentView)
        XCTAssertGreaterThan(visible.height, 0)
        XCTAssertGreaterThanOrEqual(rowRect.minY, visible.minY)
        XCTAssertLessThanOrEqual(rowRect.maxY, visible.maxY)
        XCTAssertEqual(pane.selectedIDs, [pane.entries[29].id])

        let shiftDown = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "\u{f701}", charactersIgnoringModifiers: "\u{f701}", isARepeat: false, keyCode: 125
        ))
        for _ in 0..<12 {
            table.keyDown(with: shiftDown)
            controller.configure(model: model, pane: pane, role: .main)
        }
        XCTAssertEqual(pane.selectionAnchorID, pane.entries[29].id)
        XCTAssertEqual(pane.selectionCursorID, pane.entries[41].id)
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integersIn: 29...41))
        let extendedVisible = table.convert(scroll.contentView.bounds, from: scroll.contentView)
        XCTAssertLessThanOrEqual(table.rect(ofRow: 41).maxY, extendedVisible.maxY)
    }

    func testTableRightClickPreservesGroupAndUnselectedFileReplacesIt() throws {
        let (model, pane) = makeModelAndPane()
        pane.selectedIDs = Set(pane.entries.prefix(2).map(\.id))
        let controller = AppKitFileTableController()
        controller.configure(model: model, pane: pane, role: .main)

        let menu = try XCTUnwrap(controller.entryMenu(for: 0))
        XCTAssertEqual(pane.selectedIDs.count, 2)
        XCTAssertFalse(menu.autoenablesItems)
        let copy = try XCTUnwrap(menu.items.first { $0.action == NSSelectorFromString("copyItem") })
        let target = try XCTUnwrap(copy.target as? NSObject)
        _ = target.perform(try XCTUnwrap(copy.action))
        XCTAssertEqual(pane.selectedIDs, Set(pane.entries.prefix(2).map(\.id)))
        XCTAssertEqual(Set(try XCTUnwrap(model.clipboard).urls.map(\.path)), pane.selectedIDs)

        _ = controller.entryMenu(for: 2)
        XCTAssertEqual(pane.selectedIDs, [pane.entries[2].id])
    }

    func testBlankMenuDoesNotChangeSelectionAndKeepsExplicitPasteState() throws {
        let (model, pane) = makeModelAndPane()
        pane.selectedIDs = [pane.entries[0].id]
        let controller = AppKitFileTableController()
        controller.configure(model: model, pane: pane, role: .main)

        let menu = try XCTUnwrap(controller.blankMenu())

        XCTAssertEqual(pane.selectedIDs, [pane.entries[0].id])
        XCTAssertEqual(menu.items.count, 1)
        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertEqual(menu.items.first?.isEnabled, model.canPaste(in: pane))
    }

    func testColumnsAndContextMenuFollowCurrentLanguage() throws {
        let (model, pane) = makeModelAndPane()
        let controller = AppKitFileTableController()
        for language in ["en", "ja", "zh-Hans"] {
            model.language = language
            controller.configure(model: model, pane: pane, role: .main)
            let table = try XCTUnwrap(descendant(of: NSTableView.self, in: controller.view))
            for (index, column) in FileColumn.allCases.enumerated() {
                XCTAssertTrue(table.tableColumns[index].title.hasPrefix(NativeCommandText.column(column, language: language)))
            }
            let menu = try XCTUnwrap(controller.entryMenu(for: 0))
            XCTAssertEqual(menu.items[0].title, model.commandText(.chooseApplication))
            XCTAssertEqual(menu.items[1].title, model.commandText(.copyURL))
            XCTAssertEqual(menu.items.last?.title, model.commandText(.info))
            XCTAssertEqual(controller.blankMenu()?.items.first?.title, model.commandText(.paste))
        }
    }

    func testCollectionSelectionAndContextMenuUseNativeIdentifiersAndKeepGroup() throws {
        let (model, pane) = makeModelAndPane()
        pane.selectedIDs = Set(pane.entries.prefix(2).map(\.id))
        let controller = AppKitFileCollectionController()
        controller.configure(model: model, thumbnails: model.thumbnails, pane: pane, role: .main, previewStyle: false)
        let collection = try XCTUnwrap(descendant(of: NSCollectionView.self, in: controller.view))

        XCTAssertEqual(collection.identifier, NativePaneFocus.identifier(for: pane.id))
        XCTAssertEqual(collection.selectionIndexPaths, [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)])
        XCTAssertTrue(collection.allowsEmptySelection)
        let menu = try XCTUnwrap(controller.menu(for: IndexPath(item: 0, section: 0)))
        XCTAssertEqual(pane.selectedIDs.count, 2)
        XCTAssertFalse(menu.autoenablesItems)
        _ = controller.menu(for: IndexPath(item: 2, section: 0))
        XCTAssertEqual(pane.selectedIDs, [pane.entries[2].id])
    }

    func testLoadingDirectoryDoesNotAcceptStaleNativeSelection() throws {
        let (model, pane) = makeModelAndPane()
        let controller = AppKitFileTableController()
        controller.configure(model: model, pane: pane, role: .main)
        let table = try XCTUnwrap(descendant(of: NSTableView.self, in: controller.view))
        pane.isLoading = true
        pane.entries = []
        pane.selectedIDs = []

        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        controller.endInteraction()

        XCTAssertTrue(pane.selectedIDs.isEmpty)
    }

    func testNavigationDoesNotWriteOldCollectionSelectionIntoNewDirectory() throws {
        let (model, pane) = makeModelAndPane()
        let controller = AppKitFileCollectionController()
        controller.configure(model: model, thumbnails: model.thumbnails, pane: pane, role: .main, previewStyle: false)
        let collection = try XCTUnwrap(descendant(of: NSCollectionView.self, in: controller.view))
        collection.selectionIndexPaths = [IndexPath(item: 1, section: 0)]
        pane.url = URL(fileURLWithPath: "/tmp/native-file-area-next-directory")
        pane.entries = []
        pane.selectedIDs = []

        controller.endInteraction()

        XCTAssertTrue(pane.selectedIDs.isEmpty)
    }

    func testSourceDragEndClearsOnlyItsOwningModelsPayload() {
        let (model, pane) = makeModelAndPane()
        let (otherModel, otherPane) = makeModelAndPane()
        _ = model.dragPasteboardItem(for: pane.entries[0], in: pane)
        _ = otherModel.dragPasteboardItem(for: otherPane.entries[0], in: otherPane)
        XCTAssertTrue(model.hasActiveInternalDrag)
        XCTAssertTrue(otherModel.hasActiveInternalDrag)

        NotificationCenter.default.post(name: .nativeFileDragSessionDidEnd, object: model)

        XCTAssertFalse(model.hasActiveInternalDrag)
        XCTAssertTrue(otherModel.hasActiveInternalDrag)
        NotificationCenter.default.post(name: .nativeFileDragSessionDidEnd, object: otherModel)
    }

    private func makeModelAndPane() -> (ExplorerModel, PaneState) {
        let model = ExplorerModel()
        let pane = makePane()
        model.mainPane = pane
        model.searchText = ""
        return (model, pane)
    }

    private func makePane() -> PaneState {
        let pane = PaneState(id: .main, url: URL(fileURLWithPath: "/tmp/native-file-area-tests"))
        pane.entries = makeEntries()
        return pane
    }

    private func makeEntries() -> [FileEntry] {
        ["a.txt", "b.txt", "c.txt"].map { makeEntry($0) }
    }

    private func makeEntry(_ name: String, size: Int64 = 1, typeDescription: String = "text") -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/tmp/native-file-area-tests").appendingPathComponent(name),
            name: name, isDirectory: false, isPackage: false,
            modified: nil, created: nil, size: size,
            typeDescription: typeDescription, typeIdentifier: nil
        )
    }

    private func keyEvent(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code
        ))
    }

    private func descendant<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        for child in view.subviews {
            if let result = descendant(of: type, in: child) { return result }
        }
        return nil
    }
}
