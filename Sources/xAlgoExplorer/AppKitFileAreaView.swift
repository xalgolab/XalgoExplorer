import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppKitTablePaneView: NSViewControllerRepresentable {
    @EnvironmentObject private var model: ExplorerModel
    @ObservedObject var pane: PaneState
    let role: FilePaneRole

    func makeNSViewController(context: Context) -> AppKitFileTableController {
        AppKitFileTableController()
    }

    func updateNSViewController(_ controller: AppKitFileTableController, context: Context) {
        controller.configure(model: model, pane: pane, role: role)
    }
}

struct AppKitCollectionPaneView: NSViewControllerRepresentable {
    @EnvironmentObject private var model: ExplorerModel
    @EnvironmentObject private var thumbnails: ThumbnailCache
    @ObservedObject var pane: PaneState
    let role: FilePaneRole
    let previewStyle: Bool

    func makeNSViewController(context: Context) -> AppKitFileCollectionController {
        AppKitFileCollectionController()
    }

    func updateNSViewController(_ controller: AppKitFileCollectionController, context: Context) {
        controller.configure(model: model, thumbnails: thumbnails, pane: pane, role: role, previewStyle: previewStyle)
    }
}

private enum AppKitFilePasteboard {
    static let acceptedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        NSPasteboard.PasteboardType(UTType.fileURL.identifier),
        NSPasteboard.PasteboardType(UTType.xAlgoInternalFileDrag.identifier)
    ]
}

private extension FileDropOperation {
    var nsDragOperation: NSDragOperation {
        switch self {
        case .copy:
            return .copy
        case .move:
            return .move
        }
    }
}

enum AppKitSelectionScrollTarget {
    static func tableRow(entries: [FileEntry], selectedIDs: Set<FileEntry.ID>, cursorID: FileEntry.ID?) -> Int? {
        if let cursorID, selectedIDs.contains(cursorID),
           let cursorRow = entries.firstIndex(where: { $0.id == cursorID }) {
            return cursorRow
        }
        return entries.firstIndex { selectedIDs.contains($0.id) }
    }

    static func collectionIndexPath(entries: [FileEntry], selectedIDs: Set<FileEntry.ID>, cursorID: FileEntry.ID?) -> IndexPath? {
        guard let item = tableRow(entries: entries, selectedIDs: selectedIDs, cursorID: cursorID) else {
            return nil
        }
        return IndexPath(item: item, section: 0)
    }
}

struct AppKitFileAreaChanges {
    let requiresReload: Bool
    let changedIndexes: IndexSet

    init(previous: [FileEntry], next: [FileEntry]) {
        requiresReload = previous.map(\.id) != next.map(\.id)
        changedIndexes = requiresReload ? [] : IndexSet(next.indices.filter { previous[$0] != next[$0] })
    }
}

struct AppKitFileAreaSelection: Equatable {
    let ids: Set<FileEntry.ID>
    let cursorID: FileEntry.ID?

    @MainActor init(pane: PaneState) {
        ids = pane.selectedIDs
        cursorID = pane.selectionCursorID
    }
}

enum AppKitNativeSelection {
    static func anchor(previous: FileEntry.ID?, cursor: FileEntry.ID?, selectedIDs: Set<FileEntry.ID>, extending: Bool) -> FileEntry.ID? {
        guard !selectedIDs.isEmpty else { return nil }
        if extending, let previous, selectedIDs.contains(previous) { return previous }
        return cursor
    }

    static func marqueeSelection(initial: IndexSet, intersecting: IndexSet, modifiers: NSEvent.ModifierFlags) -> IndexSet {
        if modifiers.contains(.command) { return initial.symmetricDifference(intersecting) }
        if modifiers.contains(.shift) { return initial.union(intersecting) }
        return intersecting
    }

    static func isNavigationKey(_ event: NSEvent) -> Bool {
        [123, 124, 125, 126, 115, 119, 116, 121].contains(event.keyCode)
            && event.modifierFlags.intersection([.command, .option, .control]).isEmpty
    }
}

// The model owns the drag payload; its observer must clear it on every source-session end.
extension Notification.Name {
    static let nativeFileDragSessionDidEnd = Notification.Name("xAlgoExplorer.nativeFileDragSessionDidEnd")
}

@MainActor
final class AppKitFileTableController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let scrollView = NSScrollView()
    private let tableView = AppKitFileTableView()
    private var model: ExplorerModel?
    private var pane: PaneState?
    private var role: FilePaneRole = .main
    private var entries: [FileEntry] = []
    private var isApplyingSelection = false
    private var editingEntryID: FileEntry.ID?
    private var renderedRenamingID: FileEntry.ID?
    private var lastSelection: AppKitFileAreaSelection?
    private var isSyncingColumns = false
    private var selectionEvent: NSEvent?
    private var interactionAnchorID: FileEntry.ID?
    private var interactionRow: Int?
    private var searchWasOpen = false
    private var renderedURL: URL?
    private var renderedVirtualPage: VirtualPage?

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let model, let pane, model.focusedPaneID == pane.id,
              !NativeCommandRouting.isTextInput(view.window?.firstResponder) else { return }
        view.window?.makeFirstResponder(tableView)
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        tableView.owner = self
        tableView.headerView = NSTableHeaderView()
        tableView.backgroundColor = .clear
        tableView.enclosingScrollView?.drawsBackground = false
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsColumnReordering = false
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .regular
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(openSelectedEntry)
        tableView.target = self
        tableView.registerForDraggedTypes(AppKitFilePasteboard.acceptedTypes)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        configureColumns()

        scrollView.documentView = tableView
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func configure(model: ExplorerModel, pane: PaneState, role: FilePaneRole) {
        _ = view
        let roleChanged = self.role != role
        let paneChanged = self.pane !== pane
        let restoreSearchFocus = searchWasOpen && !model.searchOpen
        searchWasOpen = model.searchOpen
        self.model = model
        self.pane = pane
        self.role = role
        renderedURL = pane.url
        renderedVirtualPage = pane.virtualPage
        tableView.identifier = NativePaneFocus.identifier(for: pane.id)
        let nextEntries = model.displayedEntries(for: pane)
        let changes = AppKitFileAreaChanges(previous: entries, next: nextEntries)
        entries = nextEntries
        let rowHeight: CGFloat = role == .main ? 34 : 28
        if tableView.rowHeight != rowHeight { tableView.rowHeight = rowHeight }
        syncColumns()
        isApplyingSelection = true
        if changes.requiresReload || paneChanged {
            tableView.contentRevision &+= 1
            tableView.reloadData()
        } else {
            var changedRows = changes.changedIndexes
            if renderedRenamingID != pane.renamingID {
                changedRows.formUnion(IndexSet(entries.indices.filter {
                    entries[$0].id == renderedRenamingID || entries[$0].id == pane.renamingID
                }))
            }
            refreshVisibleRows(roleChanged ? IndexSet(entries.indices) : changedRows)
        }
        isApplyingSelection = false
        renderedRenamingID = pane.renamingID
        if pane.renamingID == nil { editingEntryID = nil }
        if paneChanged { lastSelection = nil }
        applySelectionFromModel()
        startRenameIfNeeded()
        model.updateKeyboardColumnCount(1, in: pane)
        if restoreSearchFocus && model.focusedPaneID == pane.id && pane.renamingID == nil {
            NativePaneFocus.request(pane.id, in: view.window)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row),
              let column = FileColumn(rawValue: tableColumn?.identifier.rawValue ?? "") else {
            return nil
        }

        let entry = entries[row]
        switch column {
        case .name:
            let identifier = NSUserInterfaceItemIdentifier("name-cell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? AppKitFileNameTableCellView
                ?? AppKitFileNameTableCellView(identifier: identifier)
            cell.configure(entry: entry, pane: pane, role: role, delegate: self)
            return cell
        case .modified, .type, .size:
            let identifier = NSUserInterfaceItemIdentifier("meta-\(column.rawValue)-cell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? AppKitFileTextTableCellView
                ?? AppKitFileTextTableCellView(identifier: identifier)
            cell.configure(text: text(for: column, entry: entry), alignment: column == .size ? .right : .left)
            return cell
        }
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard let model, let pane,
              let field = sortField(for: tableColumn.identifier) else { return }
        model.setSortField(field, pane: pane)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection,
              let model,
              let pane, !pane.isLoading, pane.url == renderedURL, pane.virtualPage == renderedVirtualPage else { return }
        let selectedIDs = tableView.selectedRowIndexes
            .compactMap { entries.indices.contains($0) ? entries[$0].id : nil }
        let ids = Set(selectedIDs)
        var row = interactionRow.flatMap { tableView.selectedRowIndexes.contains($0) ? $0 : nil }
            ?? tableView.selectedRow
        if let event = selectionEvent, event.type == .keyDown {
            let added = tableView.selectedRowIndexes.filter { !pane.selectedIDs.contains(entries[$0].id) }
            if !added.isEmpty {
                row = [123, 126, 115, 116].contains(event.keyCode) ? added.first! : added.last!
            } else if let cursor = pane.selectionCursorID, let previous = entries.firstIndex(where: { $0.id == cursor }),
                      let nearest = tableView.selectedRowIndexes.min(by: { abs($0 - previous) < abs($1 - previous) }) {
                row = nearest
            }
        }
        let cursor = entries.indices.contains(row) ? entries[row].id : selectedIDs.last
        let extending = selectionEvent?.modifierFlags.intersection([.shift, .command]).isEmpty == false
        pane.selectionAnchorID = AppKitNativeSelection.anchor(
            previous: selectionEvent == nil ? pane.selectionAnchorID : interactionAnchorID,
            cursor: cursor, selectedIDs: ids, extending: extending
        )
        pane.selectionCursorID = cursor
        if pane.selectedIDs != ids { pane.selectedIDs = ids }
        lastSelection = AppKitFileAreaSelection(pane: pane)
        if model.focusedPaneID != pane.id { model.setFocus(pane.id) }
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let model, let pane, entries.indices.contains(row) else { return nil }
        return model.dragPasteboardItem(for: entries[row], in: pane)
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        let effectiveDropOperation: NSTableView.DropOperation
        if row >= 0,
           entries.indices.contains(row),
           entries[row].isDirectory,
           !entries[row].isPackage {
            tableView.setDropRow(row, dropOperation: .on)
            effectiveDropOperation = .on
        } else {
            effectiveDropOperation = dropOperation
        }
        guard let model,
              let targetDirectory = targetDirectory(forRow: row, dropOperation: effectiveDropOperation) else {
            return []
        }
        let intent = FileDropIntent(modifierFlags: NSEvent.modifierFlags)
        return model.dropOperation(from: info.draggingPasteboard, into: targetDirectory, intent: intent)?.nsDragOperation ?? []
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        let effectiveDropOperation: NSTableView.DropOperation
        if row >= 0,
           entries.indices.contains(row),
           entries[row].isDirectory,
           !entries[row].isPackage {
            effectiveDropOperation = .on
        } else {
            effectiveDropOperation = dropOperation
        }
        guard let model,
              let pane,
              let targetDirectory = targetDirectory(forRow: row, dropOperation: effectiveDropOperation) else {
            return false
        }
        model.setFocus(pane.id)
        return model.handleDrop(
            from: info.draggingPasteboard,
            into: targetDirectory,
            intent: FileDropIntent(modifierFlags: NSEvent.modifierFlags)
        )
    }

    func tableViewColumnDidResize(_ notification: Notification) {
        guard !isSyncingColumns, let model, let pane,
              let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
              let fileColumn = FileColumn(rawValue: column.identifier.rawValue) else {
            return
        }
        if abs(pane.width(for: fileColumn) - column.width) > 0.5 {
            model.setColumnWidth(column.width, for: fileColumn, in: pane)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? AppKitRenameTextField,
              let pane,
              field.entryID == pane.renamingID else { return }
        pane.renameDraft = field.stringValue
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? AppKitRenameTextField,
              let model,
              let pane,
              field.entryID == pane.renamingID else { return }
        let movement = notification.userInfo?["NSTextMovement"] as? Int
        pane.renameDraft = field.stringValue
        editingEntryID = nil
        if movement == NSTextMovement.cancel.rawValue {
            model.cancelRename(in: pane)
        } else {
            model.commitRename(in: pane)
        }
    }

    func beginInteraction(_ event: NSEvent, row: Int? = nil) {
        guard let model, let pane else { return }
        selectionEvent = event
        interactionAnchorID = pane.selectionAnchorID
        interactionRow = row
        if event.type != .keyDown || model.focusedPaneID != pane.id { model.setFocus(pane.id) }
        view.window?.makeFirstResponder(tableView)
    }

    func endInteraction() {
        tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        if selectionEvent?.type == .keyDown, let pane,
           let row = AppKitSelectionScrollTarget.tableRow(
               entries: entries, selectedIDs: pane.selectedIDs, cursorID: pane.selectionCursorID
           ) {
            tableView.scrollRowToVisible(row)
        }
        selectionEvent = nil
        interactionRow = nil
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let model, let pane else { return false }
        if model.focusedPaneID != pane.id { model.setFocus(pane.id) }
        return model.handleKeyDown(event)
    }

    func didBecomeFirstResponder() {
        guard let model, let pane, model.focusedPaneID != pane.id else { return }
        model.setFocus(pane.id)
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        NotificationCenter.default.post(name: .nativeFileDragSessionDidEnd, object: model)
    }

    func entryMenu(for row: Int) -> NSMenu? {
        guard let model, let pane, entries.indices.contains(row) else { return blankMenu() }
        if !tableView.selectedRowIndexes.contains(row) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return AppKitFileContextMenu.makeFileMenu(entry: entries[row], pane: pane, model: model)
    }

    func blankMenu() -> NSMenu? {
        guard let model, let pane else { return nil }
        return AppKitFileContextMenu.makeBlankMenu(pane: pane, model: model)
    }

    @objc private func openSelectedEntry() {
        guard let model,
              let pane,
              tableView.clickedRow >= 0,
              entries.indices.contains(tableView.clickedRow) else { return }
        model.doubleClick(entries[tableView.clickedRow], in: pane)
    }

    private func configureColumns() {
        for column in FileColumn.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = title(for: column)
            tableColumn.minWidth = column.minWidth
            tableColumn.maxWidth = .greatestFiniteMagnitude
            tableColumn.resizingMask = .userResizingMask
            tableView.addTableColumn(tableColumn)
        }
    }

    private func syncColumns() {
        guard let pane else { return }
        isSyncingColumns = true
        defer { isSyncingColumns = false }
        for tableColumn in tableView.tableColumns {
            guard let column = FileColumn(rawValue: tableColumn.identifier.rawValue) else { continue }
            let width = pane.width(for: column)
            if abs(tableColumn.width - width) > 0.5 {
                tableColumn.width = width
            }
            let nextTitle = headerTitle(for: column, pane: pane)
            if tableColumn.headerCell.stringValue != nextTitle {
                tableColumn.headerCell.stringValue = nextTitle
            }
        }
    }

    private func applySelectionFromModel() {
        guard let pane else { return }
        let selection = AppKitFileAreaSelection(pane: pane)
        let shouldReveal = lastSelection != selection
        lastSelection = selection
        let selectedRows = entries.enumerated().compactMap { index, entry in
            pane.selectedIDs.contains(entry.id) ? index : nil
        }
        let nextSelection = IndexSet(selectedRows)
        if tableView.selectedRowIndexes != nextSelection {
            isApplyingSelection = true
            tableView.selectRowIndexes(nextSelection, byExtendingSelection: false)
            isApplyingSelection = false
        }
        if shouldReveal, let row = AppKitSelectionScrollTarget.tableRow(
            entries: entries,
            selectedIDs: pane.selectedIDs,
            cursorID: pane.selectionCursorID
        ) {
            tableView.scrollRowToVisible(row)
        }
    }

    private func refreshVisibleRows(_ rows: IndexSet) {
        for row in rows {
            for (index, column) in tableView.tableColumns.enumerated() {
                guard let cell = tableView.view(atColumn: index, row: row, makeIfNecessary: false) else { continue }
                if let nameCell = cell as? AppKitFileNameTableCellView {
                    nameCell.configure(entry: entries[row], pane: pane, role: role, delegate: self)
                } else if let textCell = cell as? AppKitFileTextTableCellView,
                          let fileColumn = FileColumn(rawValue: column.identifier.rawValue) {
                    textCell.configure(text: text(for: fileColumn, entry: entries[row]), alignment: fileColumn == .size ? .right : .left)
                }
            }
        }
    }

    private func startRenameIfNeeded() {
        guard let pane,
              let renamingID = pane.renamingID,
              renamingID != editingEntryID,
              let row = entries.firstIndex(where: { $0.id == renamingID }) else {
            return
        }
        tableView.scrollRowToVisible(row)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.pane?.renamingID == renamingID,
                  self.entries.indices.contains(row), self.entries[row].id == renamingID,
                  let view = self.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? AppKitFileNameTableCellView else {
                return
            }
            self.editingEntryID = renamingID
            view.beginEditing()
        }
    }

    private func targetDirectory(forRow row: Int, dropOperation: NSTableView.DropOperation) -> URL? {
        guard let pane else { return nil }
        if row >= 0,
           entries.indices.contains(row),
           dropOperation == .on,
           entries[row].isDirectory,
           !entries[row].isPackage {
            return entries[row].url
        }
        return pane.isLocalDirectory ? pane.url : nil
    }

    private func title(for column: FileColumn) -> String {
        NativeCommandText.column(column, language: model?.language ?? "system")
    }

    private func headerTitle(for column: FileColumn, pane: PaneState) -> String {
        let title = title(for: column)
        let field: SortField
        switch column {
        case .name: field = .name
        case .modified: field = .modified
        case .type: field = .type
        case .size: field = .size
        }
        guard pane.sortField == field else { return title }
        return "\(title) \(pane.sortAscending ? "↑" : "↓")"
    }

    private func sortField(for identifier: NSUserInterfaceItemIdentifier) -> SortField? {
        switch FileColumn(rawValue: identifier.rawValue) {
        case .name: return .name
        case .modified: return .modified
        case .type: return .type
        case .size: return .size
        case .none: return nil
        }
    }

    private func text(for column: FileColumn, entry: FileEntry) -> String {
        switch column {
        case .name:
            return entry.name
        case .modified:
            return FileSystemService.formattedDate(entry.modified)
        case .type:
            return entry.typeDescription
        case .size:
            return FileSystemService.formattedSize(entry)
        }
    }
}

@MainActor
final class AppKitFileCollectionController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout, NSTextFieldDelegate {
    private let scrollView = NSScrollView()
    private let collectionView = AppKitFileCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    private var model: ExplorerModel?
    private var thumbnails: ThumbnailCache?
    private var pane: PaneState?
    private var role: FilePaneRole = .main
    private var previewStyle = false
    private var entries: [FileEntry] = []
    private var isApplyingSelection = false
    private var editingEntryID: FileEntry.ID?
    private var renderedRenamingID: FileEntry.ID?
    private var lastSelection: AppKitFileAreaSelection?
    private var selectionEvent: NSEvent?
    private var interactionAnchorID: FileEntry.ID?
    private var interactionIndexPath: IndexPath?
    private var searchWasOpen = false
    private var renderedURL: URL?
    private var renderedVirtualPage: VirtualPage?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 18, right: 8)

        collectionView.owner = self
        collectionView.autoresizingMask = [.width]
        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(AppKitFileCollectionItem.self, forItemWithIdentifier: AppKitFileCollectionItem.reuseIdentifier)
        collectionView.registerForDraggedTypes(AppKitFilePasteboard.acceptedTypes)
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)

        scrollView.documentView = collectionView
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func configure(model: ExplorerModel, thumbnails: ThumbnailCache, pane: PaneState, role: FilePaneRole, previewStyle: Bool) {
        _ = view
        let layoutChanged = self.previewStyle != previewStyle || self.role != role || self.pane == nil
        let paneChanged = self.pane !== pane
        let restoreSearchFocus = searchWasOpen && !model.searchOpen
        searchWasOpen = model.searchOpen
        self.model = model
        self.thumbnails = thumbnails
        self.pane = pane
        self.role = role
        self.previewStyle = previewStyle
        renderedURL = pane.url
        renderedVirtualPage = pane.virtualPage
        collectionView.identifier = NativePaneFocus.identifier(for: pane.id)
        let nextEntries = model.displayedEntries(for: pane)
        let changes = AppKitFileAreaChanges(previous: entries, next: nextEntries)
        entries = nextEntries
        if layoutChanged { updateLayout() }
        isApplyingSelection = true
        if changes.requiresReload || paneChanged {
            collectionView.contentRevision &+= 1
            collectionView.reloadData()
        } else {
            for indexPath in collectionView.indexPathsForVisibleItems() {
                guard entries.indices.contains(indexPath.item),
                      let item = collectionView.item(at: indexPath) as? AppKitFileCollectionItem else { continue }
                let entry = entries[indexPath.item]
                if layoutChanged || changes.changedIndexes.contains(indexPath.item)
                    || (renderedRenamingID != pane.renamingID && (entry.id == renderedRenamingID || entry.id == pane.renamingID)) {
                    item.configure(entry: entry, pane: pane, role: role, previewStyle: previewStyle, thumbnails: thumbnails, delegate: self)
                } else if previewStyle {
                    item.updateThumbnail(for: entry, thumbnails: thumbnails)
                }
            }
        }
        isApplyingSelection = false
        renderedRenamingID = pane.renamingID
        if pane.renamingID == nil { editingEntryID = nil }
        if paneChanged { lastSelection = nil }
        applySelectionFromModel()
        startRenameIfNeeded()
        updateKeyboardColumnCount()
        if restoreSearchFocus && model.focusedPaneID == pane.id && pane.renamingID == nil {
            NativePaneFocus.request(pane.id, in: view.window)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let width = scrollView.contentSize.width
        if width > 0 && abs(collectionView.frame.width - width) > 0.5 {
            collectionView.setFrameSize(NSSize(width: width, height: collectionView.frame.height))
        }
        updateKeyboardColumnCount()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let model, let pane, model.focusedPaneID == pane.id,
              !NativeCommandRouting.isTextInput(view.window?.firstResponder) else { return }
        view.window?.makeFirstResponder(collectionView)
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        entries.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: AppKitFileCollectionItem.reuseIdentifier, for: indexPath)
        guard let fileItem = item as? AppKitFileCollectionItem,
              entries.indices.contains(indexPath.item) else {
            return item
        }
        fileItem.configure(
            entry: entries[indexPath.item],
            pane: pane,
            role: role,
            previewStyle: previewStyle,
            thumbnails: thumbnails,
            delegate: self
        )
        return fileItem
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        syncSelectionToModel()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        syncSelectionToModel()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        if previewStyle {
            return NSSize(width: 156, height: 132)
        }
        return role == .main ? NSSize(width: 112, height: 96) : NSSize(width: 78, height: 78)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard let model, let pane, entries.indices.contains(indexPath.item) else { return nil }
        return model.dragPasteboardItem(for: entries[indexPath.item], in: pane)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        let index = proposedDropIndexPath.pointee.item
        if entries.indices.contains(index),
           entries[index].isDirectory,
           !entries[index].isPackage {
            proposedDropOperation.pointee = .on
        }

        guard let model,
              let targetDirectory = targetDirectory(for: proposedDropIndexPath.pointee as IndexPath, dropOperation: proposedDropOperation.pointee) else {
            return []
        }
        let intent = FileDropIntent(modifierFlags: NSEvent.modifierFlags)
        return model.dropOperation(from: draggingInfo.draggingPasteboard, into: targetDirectory, intent: intent)?.nsDragOperation ?? []
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        guard let model,
              let pane,
              let targetDirectory = targetDirectory(for: indexPath, dropOperation: dropOperation) else {
            return false
        }
        model.setFocus(pane.id)
        return model.handleDrop(
            from: draggingInfo.draggingPasteboard,
            into: targetDirectory,
            intent: FileDropIntent(modifierFlags: NSEvent.modifierFlags)
        )
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? AppKitRenameTextField,
              let pane,
              field.entryID == pane.renamingID else { return }
        pane.renameDraft = field.stringValue
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? AppKitRenameTextField,
              let model,
              let pane,
              field.entryID == pane.renamingID else { return }
        let movement = notification.userInfo?["NSTextMovement"] as? Int
        pane.renameDraft = field.stringValue
        editingEntryID = nil
        if movement == NSTextMovement.cancel.rawValue {
            model.cancelRename(in: pane)
        } else {
            model.commitRename(in: pane)
        }
    }

    func beginInteraction(_ event: NSEvent, indexPath: IndexPath? = nil) {
        guard let model, let pane else { return }
        selectionEvent = event
        interactionAnchorID = pane.selectionAnchorID
        interactionIndexPath = indexPath
        if event.type != .keyDown || model.focusedPaneID != pane.id { model.setFocus(pane.id) }
        view.window?.makeFirstResponder(collectionView)
    }

    func endInteraction() {
        syncSelectionToModel()
        selectionEvent = nil
        interactionIndexPath = nil
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let model, let pane else { return false }
        if model.focusedPaneID != pane.id { model.setFocus(pane.id) }
        return model.handleKeyDown(event)
    }

    func didBecomeFirstResponder() {
        guard let model, let pane, model.focusedPaneID != pane.id else { return }
        model.setFocus(pane.id)
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        NotificationCenter.default.post(name: .nativeFileDragSessionDidEnd, object: model)
    }

    func openEntry(at indexPath: IndexPath) {
        guard let model, let pane, entries.indices.contains(indexPath.item) else { return }
        model.doubleClick(entries[indexPath.item], in: pane)
    }

    func menu(for indexPath: IndexPath?) -> NSMenu? {
        guard let model, let pane else { return nil }
        guard let indexPath,
              entries.indices.contains(indexPath.item) else {
            return AppKitFileContextMenu.makeBlankMenu(pane: pane, model: model)
        }
        if !collectionView.selectionIndexPaths.contains(indexPath) {
            collectionView.selectionIndexPaths = [indexPath]
            syncSelectionToModel()
        }
        return AppKitFileContextMenu.makeFileMenu(entry: entries[indexPath.item], pane: pane, model: model)
    }

    func syncSelectionToModel() {
        guard !isApplyingSelection,
              let model,
              let pane, !pane.isLoading, pane.url == renderedURL, pane.virtualPage == renderedVirtualPage else { return }
        let selectedIDs = collectionView.selectionIndexPaths
            .sorted()
            .compactMap { entries.indices.contains($0.item) ? entries[$0.item].id : nil }
        let ids = Set(selectedIDs)
        let clickedID = interactionIndexPath.flatMap { indexPath in
            entries.indices.contains(indexPath.item) && collectionView.selectionIndexPaths.contains(indexPath)
                ? entries[indexPath.item].id : nil
        }
        let movingBackward = selectionEvent.map { $0.type == .keyDown && [123, 126, 115, 116].contains($0.keyCode) } ?? false
        let added = selectedIDs.filter { !pane.selectedIDs.contains($0) }
        let cursor = clickedID ?? (movingBackward ? selectedIDs.first : (added.last ?? selectedIDs.last))
        let extending = selectionEvent?.modifierFlags.intersection([.shift, .command]).isEmpty == false
        pane.selectionAnchorID = AppKitNativeSelection.anchor(
            previous: selectionEvent == nil ? pane.selectionAnchorID : interactionAnchorID,
            cursor: cursor, selectedIDs: ids, extending: extending
        )
        pane.selectionCursorID = cursor
        if pane.selectedIDs != ids { pane.selectedIDs = ids }
        lastSelection = AppKitFileAreaSelection(pane: pane)
        if model.focusedPaneID != pane.id { model.setFocus(pane.id) }
    }

    private func applySelectionFromModel() {
        guard let pane else { return }
        let selection = AppKitFileAreaSelection(pane: pane)
        let shouldReveal = lastSelection != selection
        lastSelection = selection
        let indexPaths = Set(entries.enumerated().compactMap { index, entry in
            pane.selectedIDs.contains(entry.id) ? IndexPath(item: index, section: 0) : nil
        })
        if collectionView.selectionIndexPaths != indexPaths {
            isApplyingSelection = true
            collectionView.selectionIndexPaths = indexPaths
            isApplyingSelection = false
        }
        if shouldReveal, let indexPath = AppKitSelectionScrollTarget.collectionIndexPath(
            entries: entries,
            selectedIDs: pane.selectedIDs,
            cursorID: pane.selectionCursorID
        ) {
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
        }
    }

    private func startRenameIfNeeded() {
        guard let pane,
              let renamingID = pane.renamingID,
              renamingID != editingEntryID,
              let index = entries.firstIndex(where: { $0.id == renamingID }) else {
            return
        }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.pane?.renamingID == renamingID,
                  self.entries.indices.contains(index), self.entries[index].id == renamingID,
                  let item = self.collectionView.item(at: indexPath) as? AppKitFileCollectionItem else {
                return
            }
            self.editingEntryID = renamingID
            item.beginEditing()
        }
    }

    private func updateLayout() {
        layout.itemSize = previewStyle
            ? NSSize(width: 156, height: 132)
            : (role == .main ? NSSize(width: 112, height: 96) : NSSize(width: 78, height: 78))
        layout.minimumInteritemSpacing = previewStyle ? 16 : (role == .main ? 4 : 2)
        layout.minimumLineSpacing = previewStyle ? 18 : (role == .main ? 8 : 4)
        layout.sectionInset = previewStyle
            ? NSEdgeInsets(top: 12, left: 14, bottom: 30, right: 14)
            : NSEdgeInsets(top: role == .main ? 8 : 6, left: role == .main ? 8 : 6, bottom: 18, right: role == .main ? 8 : 6)
        layout.invalidateLayout()
    }

    private func updateKeyboardColumnCount() {
        guard let model, let pane else { return }
        let width = collectionView.enclosingScrollView?.contentSize.width ?? collectionView.bounds.width
        let itemWidth = layout.itemSize.width
        let spacing = layout.minimumInteritemSpacing
        let usable = max(0, width - layout.sectionInset.left - layout.sectionInset.right)
        let count = max(1, Int((usable + spacing) / (itemWidth + spacing)))
        model.updateKeyboardColumnCount(count, in: pane)
    }

    private func targetDirectory(for indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> URL? {
        guard let pane else { return nil }
        if dropOperation == .on,
           entries.indices.contains(indexPath.item),
           entries[indexPath.item].isDirectory,
           !entries[indexPath.item].isPackage {
            return entries[indexPath.item].url
        }
        return pane.isLocalDirectory ? pane.url : nil
    }
}

@MainActor
private enum AppKitFileMarquee {
    static func track(
        in view: NSView,
        event: NSEvent,
        initialSelection: IndexSet,
        isValid: () -> Bool,
        indexesInRect: (NSRect) -> IndexSet,
        applySelection: (IndexSet) -> Void
    ) {
        guard let window = view.window else { return }
        let origin = view.convert(event.locationInWindow, from: nil)
        let overlay = AppKitFileMarqueeView(frame: .zero)
        view.addSubview(overlay)
        defer { overlay.removeFromSuperview() }
        let modifiers = event.modifierFlags
        applySelection(AppKitNativeSelection.marqueeSelection(initial: initialSelection, intersecting: [], modifiers: modifiers))
        var lastEvent = event
        var isDragging = false

        // Timeout callbacks keep native autoscroll running even when the pointer stops moving.
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp, .keyDown], timeout: 1.0 / 60, mode: .eventTracking) { nextEvent, stop in
            guard isValid() else {
                stop.pointee = true
                return
            }
            guard view.window === window, window.isVisible, NSApp.isActive else {
                applySelection(initialSelection)
                stop.pointee = true
                return
            }
            if let nextEvent {
                if nextEvent.type == .keyDown {
                    if nextEvent.keyCode == 53 {
                        applySelection(initialSelection)
                        stop.pointee = true
                    }
                    return
                }
                lastEvent = nextEvent
                if nextEvent.type == .leftMouseUp { stop.pointee = true }
            } else if NSEvent.pressedMouseButtons & 1 == 0 {
                stop.pointee = true
                return
            }
            let point = view.convert(lastEvent.locationInWindow, from: nil)
            isDragging = isDragging || hypot(point.x - origin.x, point.y - origin.y) >= 4
            guard isDragging else { return }
            if !stop.pointee.boolValue { _ = view.autoscroll(with: lastEvent) }
            let current = view.convert(lastEvent.locationInWindow, from: nil)
            let rect = NSRect(x: min(origin.x, current.x), y: min(origin.y, current.y), width: abs(current.x - origin.x), height: abs(current.y - origin.y))
            overlay.frame = rect
            overlay.needsDisplay = true
            applySelection(AppKitNativeSelection.marqueeSelection(initial: initialSelection, intersecting: indexesInRect(rect), modifiers: modifiers))
        }
    }
}

private final class AppKitFileMarqueeView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).setFill()
        bounds.fill()
        NSColor.selectedContentBackgroundColor.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}

private final class AppKitFileTableView: NSTableView {
    weak var owner: AppKitFileTableController?
    var contentRevision = 0

    override func scrollRowToVisible(_ row: Int) {
        guard row >= 0, row < numberOfRows, let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        let visible = convert(clipView.bounds, from: clipView)
        guard visible.height > 0 else { return }
        let target = rect(ofRow: row)
        var y = visible.minY
        if target.minY < visible.minY { y = target.minY }
        if target.maxY > visible.maxY { y = target.maxY - visible.height }
        guard abs(y - visible.minY) > 0.5 else { return }
        // Avoid stacking animated native scroll requests during rapid key repeats.
        var origin = clipView.bounds.origin
        origin.y = clipView.convert(NSPoint(x: visible.minX, y: y), from: self).y
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { owner?.didBecomeFirstResponder() }
        return accepted
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        owner?.beginInteraction(event, row: row >= 0 ? row : nil)
        defer { owner?.endInteraction() }
        if row == -1 && !event.modifierFlags.contains(.control) {
            let revision = contentRevision
            AppKitFileMarquee.track(in: self, event: event, initialSelection: selectedRowIndexes, isValid: { self.contentRevision == revision }) { rect in
                let range = self.rows(in: rect)
                guard range.location != NSNotFound else { return [] }
                return IndexSet(integersIn: range.location..<min(NSMaxRange(range), self.numberOfRows))
            } applySelection: { indexes in
                if self.selectedRowIndexes != indexes {
                    self.selectRowIndexes(indexes, byExtendingSelection: false)
                }
            }
        } else {
            super.mouseDown(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if AppKitNativeSelection.isNavigationKey(event) {
            owner?.beginInteraction(event)
            super.keyDown(with: event)
            owner?.endInteraction()
        } else if owner?.handleKeyDown(event) != true {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        owner?.beginInteraction(event, row: row >= 0 ? row : nil)
        defer { owner?.endInteraction() }
        return row >= 0 ? owner?.entryMenu(for: row) : owner?.blankMenu()
    }
}

private final class AppKitFileCollectionView: NSCollectionView {
    weak var owner: AppKitFileCollectionController?
    var contentRevision = 0

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { owner?.didBecomeFirstResponder() }
        return accepted
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let indexPath = indexPathForItem(at: point)
        owner?.beginInteraction(event, indexPath: indexPath)
        defer { owner?.endInteraction() }
        if indexPath == nil && !event.modifierFlags.contains(.control) {
            let revision = contentRevision
            AppKitFileMarquee.track(in: self, event: event, initialSelection: IndexSet(selectionIndexPaths.map(\.item)), isValid: { self.contentRevision == revision }) { rect in
                let attributes = self.collectionViewLayout?.layoutAttributesForElements(in: rect) ?? []
                return IndexSet(attributes.filter { $0.representedElementCategory == .item }.compactMap { $0.indexPath?.item })
            } applySelection: { indexes in
                let paths = Set(indexes.map { IndexPath(item: $0, section: 0) })
                if self.selectionIndexPaths != paths {
                    self.selectionIndexPaths = paths
                    self.owner?.syncSelectionToModel()
                }
            }
        } else {
            super.mouseDown(with: event)
        }
        if event.clickCount >= 2, let indexPath {
            owner?.openEntry(at: indexPath)
        }
    }

    override func keyDown(with event: NSEvent) {
        if AppKitNativeSelection.isNavigationKey(event) {
            owner?.beginInteraction(event)
            super.keyDown(with: event)
            owner?.endInteraction()
        } else if owner?.handleKeyDown(event) != true {
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        owner?.beginInteraction(event, indexPath: indexPathForItem(at: point))
        defer { owner?.endInteraction() }
        return owner?.menu(for: indexPathForItem(at: point))
    }
}

private final class AppKitFileNameTableCellView: NSTableCellView {
    private let iconView = NSImageView()
    let nameField = AppKitRenameTextField()
    private lazy var iconWidth = iconView.widthAnchor.constraint(equalToConstant: 22)
    private lazy var iconHeight = iconView.heightAnchor.constraint(equalToConstant: 22)

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(entry: FileEntry, pane: PaneState?, role: FilePaneRole, delegate: NSTextFieldDelegate) {
        iconView.image = FileSystemService.appIcon(for: entry)
        nameField.entryID = entry.id
        if nameField.currentEditor() == nil {
            nameField.stringValue = pane?.renamingID == entry.id ? (pane?.renameDraft ?? entry.name) : entry.name
        }
        nameField.delegate = delegate
        nameField.isEditable = pane?.renamingID == entry.id
        nameField.isSelectable = pane?.renamingID == entry.id
        nameField.font = .systemFont(ofSize: role == .main ? 13 : 12, weight: .regular)
        iconWidth.constant = role == .main ? 22 : 18
        iconHeight.constant = iconWidth.constant
        toolTip = entry.url.path
    }

    func beginEditing() {
        nameField.isEditable = true
        nameField.isSelectable = true
        window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.lineBreakMode = .byTruncatingTail
        nameField.usesSingleLineMode = true
        nameField.focusRingType = .none

        addSubview(iconView)
        addSubview(nameField)
        textField = nameField
        imageView = iconView

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidth,
            iconHeight,
            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private final class AppKitFileTextTableCellView: NSTableCellView {
    private let valueField = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(text: String, alignment: NSTextAlignment) {
        valueField.stringValue = text
        valueField.alignment = alignment
    }

    private func setup() {
        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.font = .systemFont(ofSize: 12)
        valueField.textColor = .secondaryLabelColor
        valueField.lineBreakMode = .byTruncatingTail
        addSubview(valueField)
        textField = valueField
        NSLayoutConstraint.activate([
            valueField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private final class AppKitFileCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("file-collection-item")

    private let container = NSView()
    private let iconImageView = NSImageView()
    private let nameField = AppKitRenameTextField()
    private var entryID: FileEntry.ID?
    private lazy var iconWidth = iconImageView.widthAnchor.constraint(equalToConstant: 44)
    private lazy var iconHeight = iconImageView.heightAnchor.constraint(equalToConstant: 44)

    override func loadView() {
        view = container
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = NSColor.clear.cgColor

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.alignment = .center
        nameField.lineBreakMode = .byTruncatingTail
        nameField.maximumNumberOfLines = 2
        nameField.focusRingType = .none

        container.addSubview(iconImageView)
        container.addSubview(nameField)

        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            iconImageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconWidth,
            iconHeight,
            nameField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            nameField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            nameField.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 6),
            nameField.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -6)
        ])
    }

    override var isSelected: Bool {
        didSet {
            updateSelectionBackground()
        }
    }

    func configure(
        entry: FileEntry,
        pane: PaneState?,
        role: FilePaneRole,
        previewStyle: Bool,
        thumbnails: ThumbnailCache?,
        delegate: NSTextFieldDelegate
    ) {
        entryID = entry.id
        nameField.entryID = entry.id
        if nameField.currentEditor() == nil {
            nameField.stringValue = pane?.renamingID == entry.id ? (pane?.renameDraft ?? entry.name) : entry.name
        }
        nameField.delegate = delegate
        nameField.isEditable = pane?.renamingID == entry.id
        nameField.isSelectable = pane?.renamingID == entry.id
        nameField.font = .systemFont(ofSize: previewStyle ? 12 : (role == .main ? 13 : 11))
        container.toolTip = entry.url.path

        if previewStyle {
            thumbnails?.request(url: entry.url, size: CGSize(width: 280, height: 224))
            iconImageView.image = thumbnails?.image(for: entry.url) ?? FileSystemService.appIcon(for: entry)
        } else {
            iconImageView.image = FileSystemService.appIcon(for: entry)
        }

        let imageSize: CGFloat = previewStyle ? 82 : (role == .main ? 44 : 32)
        iconWidth.constant = imageSize
        iconHeight.constant = imageSize
        updateSelectionBackground()
    }

    func updateThumbnail(for entry: FileEntry, thumbnails: ThumbnailCache?) {
        guard entryID == entry.id, let image = thumbnails?.image(for: entry.url), iconImageView.image !== image else { return }
        iconImageView.image = image
    }

    func beginEditing() {
        nameField.isEditable = true
        nameField.isSelectable = true
        view.window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    private func updateSelectionBackground() {
        container.layer?.backgroundColor = isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.72).cgColor
            : NSColor.clear.cgColor
    }
}

private final class AppKitRenameTextField: NSTextField {
    var entryID: FileEntry.ID?
}

@MainActor
private enum AppKitFileContextMenu {
    static func makeFileMenu(entry: FileEntry, pane: PaneState, model: ExplorerModel) -> NSMenu {
        let menu = AppKitActionMenu()
        menu.autoenablesItems = false
        let target = AppKitMenuActionTarget(model: model, pane: pane, entry: entry)
        menu.actionTarget = target
        menu.addItem(item(model.commandText(.chooseApplication), action: #selector(AppKitMenuActionTarget.chooseApplication), target: target))
        menu.addItem(item(model.commandText(.copyURL), action: #selector(AppKitMenuActionTarget.copyURL), target: target))
        menu.addItem(.separator())
        menu.addItem(item(model.commandText(.cut), action: #selector(AppKitMenuActionTarget.cut), target: target))
        menu.addItem(item(model.commandText(.copy), action: #selector(AppKitMenuActionTarget.copyItem), target: target))
        let paste = item(model.commandText(.paste), action: #selector(AppKitMenuActionTarget.paste), target: target)
        paste.isEnabled = model.canPaste(in: pane)
        menu.addItem(paste)
        menu.addItem(.separator())
        let trash = item(model.commandText(.moveToTrash), action: #selector(AppKitMenuActionTarget.trash), target: target)
        trash.isEnabled = !model.isPerformingFileOperation
        menu.addItem(trash)
        let rename = item(model.commandText(.rename), action: #selector(AppKitMenuActionTarget.rename), target: target)
        rename.isEnabled = !model.isPerformingFileOperation
        menu.addItem(rename)
        menu.addItem(item(model.commandText(.info), action: #selector(AppKitMenuActionTarget.info), target: target))
        return menu
    }

    static func makeBlankMenu(pane: PaneState, model: ExplorerModel) -> NSMenu {
        let menu = AppKitActionMenu()
        menu.autoenablesItems = false
        let target = AppKitMenuActionTarget(model: model, pane: pane, entry: nil)
        menu.actionTarget = target
        let paste = item(model.commandText(.paste), action: #selector(AppKitMenuActionTarget.paste), target: target)
        paste.isEnabled = model.canPaste(in: pane)
        menu.addItem(paste)
        return menu
    }

    private static func item(_ title: String, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }
}

@MainActor
private final class AppKitActionMenu: NSMenu {
    var actionTarget: AppKitMenuActionTarget?
}

@MainActor
private final class AppKitMenuActionTarget: NSObject {
    private weak var model: ExplorerModel?
    private weak var pane: PaneState?
    private let entry: FileEntry?

    init(model: ExplorerModel, pane: PaneState, entry: FileEntry?) {
        self.model = model
        self.pane = pane
        self.entry = entry
    }

    @objc func chooseApplication() {
        guard let model, let pane, let entry else { return }
        model.chooseApplicationAndOpen(entry, in: pane)
    }

    @objc func copyURL() {
        guard let model, let entry else { return }
        model.copyURL(of: entry)
    }

    @objc func cut() {
        guard let model, let pane, let entry else { return }
        focusSelection(containing: entry, pane: pane, model: model)
        model.cutSelection(in: pane)
    }

    @objc func copyItem() {
        guard let model, let pane, let entry else { return }
        focusSelection(containing: entry, pane: pane, model: model)
        model.copySelection(in: pane)
    }

    @objc func paste() {
        guard let model, let pane, model.canPaste(in: pane) else { return }
        let destination = entry.flatMap { $0.isDirectory && !$0.isPackage ? $0.url : nil } ?? pane.url
        model.setFocus(pane.id)
        model.pasteClipboard(in: pane, to: destination)
    }

    @objc func trash() {
        guard let model, let pane, let entry, !model.isPerformingFileOperation else { return }
        focusSelection(containing: entry, pane: pane, model: model)
        model.trashSelection()
    }

    @objc func rename() {
        guard let model, let pane, let entry, !model.isPerformingFileOperation else { return }
        model.beginRename(entry, in: pane)
    }

    @objc func info() {
        guard let model, let entry else { return }
        model.showInfo(for: entry)
    }

    private func focusSelection(containing entry: FileEntry, pane: PaneState, model: ExplorerModel) {
        model.setFocus(pane.id)
        if !pane.selectedIDs.contains(entry.id) {
            model.select(entry, in: pane, modifiers: [])
        }
    }
}
