import AppKit
import Combine
import Foundation
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ExplorerModel: ObservableObject {
    @Published var mainPane: PaneState
    @Published var assistTopPane: PaneState
    @Published var assistBottomPane: PaneState
    @Published var focusedPaneID: PaneID = .main
    @Published var assistOpen: Bool
    @Published var hideRail: Bool
    @Published var autoCheckUpdates: Bool
    @Published var language: String
    @Published var searchOpen = false
    @Published var searchText = ""
    @Published var paneInteractionRevision = 0
    @Published var clipboard: ClipboardPayload?
    @Published var error: ExplorerError?
    @Published var fileInfo: FileInfoSheet?
    @Published var showingAbout = false
    @Published private(set) var isPerformingFileOperation = false
    @Published private var sidebarShortcutURLs: [URL] = []
    @Published private var hiddenDefaultSidebarTargetIDs: Set<String> = []
    private var activeInternalDragPayload: InternalFileDragPayload?
    private var activeInternalDragExpiresAt: Date?
    private weak var activeInternalDragProvider: NSItemProvider?
    private var clipboardPasteboardChangeCount: Int?
    private var reloadTasks: [PaneID: Task<Void, Never>] = [:]
    private var reloadGenerations: [PaneID: UUID] = [:]
    private let fileOperationWorker = FileOperationWorker()
    private var fileOperationTask: Task<Void, Never>?
    private var systemObservers: Set<AnyCancellable> = []
    @Published private var mountedVolumeURLs = FileSystemService.mountedVolumes()

    let thumbnails = ThumbnailCache()

    private static let sidebarShortcutPathsKey = "sidebarShortcutPaths"
    private static let hiddenDefaultSidebarTargetIDsKey = "hiddenDefaultSidebarTargetIDs"
    private let defaults = UserDefaults.standard
    private let homeURL = FileManager.default.homeDirectoryForCurrentUser
    private var lastClickedEntryID: FileEntry.ID?
    private var lastClickedAt: Date = .distantPast

    init() {
        let mainURL = Self.storedURL("mainPath") ?? homeURL
        let topURL = Self.storedURL("assistTopPath") ?? mainURL
        let bottomURL = Self.storedURL("assistBottomPath") ?? mainURL

        self.mainPane = PaneState(
            id: .main,
            url: mainURL,
            viewMode: Self.storedViewMode("mainViewMode") ?? .list,
            sortField: Self.storedSortField("mainSortField") ?? .name,
            sortAscending: UserDefaults.standard.object(forKey: "mainSortAscending") as? Bool ?? true
        )
        self.assistTopPane = PaneState(
            id: .assistTop,
            url: topURL,
            viewMode: Self.storedViewMode("assistTopViewMode") ?? .files,
            sortField: Self.storedSortField("assistTopSortField") ?? .name,
            sortAscending: UserDefaults.standard.object(forKey: "assistTopSortAscending") as? Bool ?? true
        )
        self.assistBottomPane = PaneState(
            id: .assistBottom,
            url: bottomURL,
            viewMode: Self.storedViewMode("assistBottomViewMode") ?? .list,
            sortField: Self.storedSortField("assistBottomSortField") ?? .name,
            sortAscending: UserDefaults.standard.object(forKey: "assistBottomSortAscending") as? Bool ?? true
        )

        self.assistOpen = defaults.object(forKey: "assistOpen") as? Bool ?? false
        self.hideRail = defaults.object(forKey: "hideRail") as? Bool ?? false
        self.autoCheckUpdates = defaults.object(forKey: "autoCheckUpdates") as? Bool ?? false
        self.language = defaults.string(forKey: "language") ?? "system"
        self.sidebarShortcutURLs = Self.storedSidebarShortcutURLs()
        self.hiddenDefaultSidebarTargetIDs = Self.storedHiddenDefaultSidebarTargetIDs()

        applyStoredColumnWidths(mainPane)
        applyStoredColumnWidths(assistTopPane)
        applyStoredColumnWidths(assistBottomPane)

        observeSystemChanges()
        reloadAll()
    }

    var focusedPane: PaneState {
        pane(focusedPaneID)
    }

    var hasSelection: Bool {
        !focusedPane.selectedIDs.isEmpty
    }

    var canPaste: Bool {
        canPaste(in: focusedPane)
    }

    var canRenameSelection: Bool {
        focusedPane.selectedIDs.count == 1 && focusedPane.isLocalDirectory
    }

    func hasSelection(in pane: PaneState) -> Bool {
        !pane.selectedIDs.isEmpty
    }

    func canPaste(in pane: PaneState) -> Bool {
        !isPerformingFileOperation && pane.isLocalDirectory && currentClipboardPayload() != nil
    }

    var availableViewModesForFocusedPane: [ExplorerViewMode] {
        focusedPaneID == .main ? ExplorerViewMode.allCases : [.list, .files]
    }

    var allDefaultSidebarTargets: [SidebarTarget] {
        let fm = FileManager.default
        return [
            SidebarTarget(id: "home", title: text(.sidebarHome), symbolName: "house", kind: .folder(homeURL), group: .appDefault),
            SidebarTarget(id: "pictures", title: text(.sidebarPictures), symbolName: "photo", kind: .folder(fm.urls(for: .picturesDirectory, in: .userDomainMask).first ?? homeURL), group: .appDefault),
            SidebarTarget(id: "desktop", title: text(.sidebarDesktop), symbolName: "desktopcomputer", kind: .folder(fm.urls(for: .desktopDirectory, in: .userDomainMask).first ?? homeURL), group: .appDefault),
            SidebarTarget(id: "downloads", title: text(.sidebarDownloads), symbolName: "arrow.down.to.line", kind: .folder(fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? homeURL), group: .appDefault),
            SidebarTarget(id: "documents", title: text(.sidebarDocuments), symbolName: "doc.text", kind: .folder(fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? homeURL), group: .appDefault),
            SidebarTarget(id: "music", title: text(.sidebarMusic), symbolName: "music.note", kind: .folder(fm.urls(for: .musicDirectory, in: .userDomainMask).first ?? homeURL), group: .appDefault),
            SidebarTarget(id: "movies", title: text(.sidebarMovies), symbolName: "play.rectangle", kind: .folder(fm.urls(for: .moviesDirectory, in: .userDomainMask).first ?? homeURL), group: .appDefault)
        ]
    }

    var defaultSidebarTargets: [SidebarTarget] {
        allDefaultSidebarTargets.filter { !hiddenDefaultSidebarTargetIDs.contains($0.id) }
    }

    var userSidebarTargets: [SidebarTarget] {
        sidebarShortcutURLs.map { url in
            SidebarTarget(
                id: "shortcut-\(url.path)",
                title: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                symbolName: sidebarShortcutSymbol(for: url),
                kind: isDirectory(url) ? .folder(url) : .file(url),
                group: .userShortcut
            )
        }
    }

    var utilitySidebarTargets: [SidebarTarget] {
        var targets = mountedVolumeURLs
            .filter { $0.path != "/" }
            .map {
                SidebarTarget(
                    id: "volume-\($0.path)",
                    title: $0.lastPathComponent,
                    symbolName: "externaldrive",
                    kind: .folder($0),
                    group: .mountedVolume
                )
            }
        targets.append(SidebarTarget(id: "network", title: text(.sidebarNetwork), symbolName: "network", kind: .network))
        return targets
    }

    var sidebarTargets: [SidebarTarget] {
        defaultSidebarTargets + userSidebarTargets + utilitySidebarTargets
    }

    func pane(_ id: PaneID) -> PaneState {
        switch id {
        case .main: mainPane
        case .assistTop: assistTopPane
        case .assistBottom: assistBottomPane
        }
    }

    func setFocus(_ id: PaneID) {
        if focusedPaneID != id { focusedPaneID = id }
        paneInteractionRevision += 1
    }

    private func observeSystemChanges() {
        NotificationCenter.default.publisher(for: .nativeFileDragSessionDidEnd)
            .sink { [weak self] notification in
                guard let self, notification.object as? ExplorerModel === self else { return }
                self.clearActiveInternalDrag()
            }
            .store(in: &systemObservers)

        let workspace = NSWorkspace.shared.notificationCenter
        Publishers.Merge3(
            workspace.publisher(for: NSWorkspace.didMountNotification),
            workspace.publisher(for: NSWorkspace.didUnmountNotification),
            workspace.publisher(for: NSWorkspace.didRenameVolumeNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.mountedVolumeURLs = FileSystemService.mountedVolumes()
        }
        .store(in: &systemObservers)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &systemObservers)
    }

    func toggleAssist() {
        assistOpen.toggle()
        defaults.set(assistOpen, forKey: "assistOpen")
        if assistOpen {
            if assistTopPane.entries.isEmpty {
                navigate(assistTopPane, to: mainPane.url, pushHistory: false)
            }
            if assistBottomPane.entries.isEmpty {
                navigate(assistBottomPane, to: mainPane.url, pushHistory: false)
            }
        } else if focusedPaneID.isAssist {
            focusedPaneID = .main
        }
    }

    func setHideRail(_ value: Bool) {
        hideRail = value
        defaults.set(value, forKey: "hideRail")
    }

    func setAutoCheckUpdates(_ value: Bool) {
        autoCheckUpdates = value
        defaults.set(value, forKey: "autoCheckUpdates")
    }

    func setLanguage(_ value: String) {
        language = value
        defaults.set(value, forKey: "language")
    }

    func showAbout() {
        showingAbout = true
    }

    func text(_ key: AppTextKey) -> String {
        AppText.localized(key, language: language)
    }

    func openSidebarTarget(_ target: SidebarTarget) {
        focusedPaneID = .main
        switch target.kind {
        case let .folder(url):
            mainPane.virtualPage = nil
            navigate(mainPane, to: url)
        case let .file(url):
            NSWorkspace.shared.open(url)
        case .network:
            mainPane.backStack.append(mainPane.url)
            mainPane.forwardStack.removeAll()
            mainPane.virtualPage = .network
            mainPane.selectedIDs.removeAll()
            persist(mainPane)
        }
    }

    func removeSidebarShortcut(_ target: SidebarTarget) {
        guard target.isUserShortcut else { return }
        switch target.kind {
        case let .folder(url), let .file(url):
            sidebarShortcutURLs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
            persistSidebarShortcuts()
        case .network:
            return
        }
    }

    func hideDefaultSidebarTarget(_ target: SidebarTarget) {
        guard target.group == .appDefault else { return }
        hiddenDefaultSidebarTargetIDs.insert(target.id)
        persistHiddenDefaultSidebarTargets()
    }

    func setDefaultSidebarTarget(_ target: SidebarTarget, visible: Bool) {
        guard target.group == .appDefault else { return }
        if visible {
            hiddenDefaultSidebarTargetIDs.remove(target.id)
        } else {
            hiddenDefaultSidebarTargetIDs.insert(target.id)
        }
        persistHiddenDefaultSidebarTargets()
    }

    func isDefaultSidebarTargetVisible(_ target: SidebarTarget) -> Bool {
        target.group == .appDefault && !hiddenDefaultSidebarTargetIDs.contains(target.id)
    }

    func restoreDefaultSidebarTargets() {
        hiddenDefaultSidebarTargetIDs.removeAll()
        persistHiddenDefaultSidebarTargets()
    }

    var hasHiddenDefaultSidebarTargets: Bool {
        !hiddenDefaultSidebarTargetIDs.isEmpty
    }

    func ejectVolume(_ target: SidebarTarget) {
        guard target.group == .mountedVolume, case let .folder(url) = target.kind else { return }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        } catch {
            showError("推出失败", error)
        }
    }

    func displayedEntries(for pane: PaneState) -> [FileEntry] {
        guard pane.id == .main, !searchText.isEmpty else {
            return pane.entries
        }
        return pane.entries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    func reloadAll() {
        reload(mainPane)
        reload(assistTopPane)
        reload(assistBottomPane)
    }

    func reload(_ pane: PaneState) {
        reloadTasks[pane.id]?.cancel()
        let generation = UUID()
        reloadGenerations[pane.id] = generation
        guard pane.virtualPage == nil else {
            pane.entries = []
            pane.errorMessage = nil
            pane.isLoading = false
            reloadTasks[pane.id] = nil
            return
        }

        let url = pane.url
        pane.isLoading = true
        pane.errorMessage = nil
        // Only the latest request for this pane may publish directory contents.
        reloadTasks[pane.id] = Task { [weak self, weak pane] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try FileSystemService.entries(in: url) }
            }.value
            guard !Task.isCancelled, let self, let pane,
                  self.reloadGenerations[pane.id] == generation,
                  pane.url == url, pane.virtualPage == nil else { return }
            switch result {
            case .success(let loaded):
                pane.entries = FileSystemService.sort(loaded, by: pane.sortField, ascending: pane.sortAscending)
                let availableIDs = Set(pane.entries.map(\.id))
                pane.selectedIDs.formIntersection(availableIDs)
                if let anchor = pane.selectionAnchorID, !availableIDs.contains(anchor) {
                    pane.selectionAnchorID = nil
                }
                if let cursor = pane.selectionCursorID, !availableIDs.contains(cursor) {
                    pane.selectionCursorID = pane.selectedIDs.first
                }
            case .failure(let error):
                pane.entries = []
                pane.selectedIDs.removeAll()
                pane.errorMessage = error.localizedDescription
            }
            pane.isLoading = false
            self.reloadTasks[pane.id] = nil
        }
        persist(pane)
    }

    func waitForPendingReloads() async {
        for task in Array(reloadTasks.values) { await task.value }
    }

    func refreshFocusedPane() {
        reload(focusedPane)
    }

    func navigate(_ pane: PaneState, to url: URL, pushHistory: Bool = true) {
        guard url.isFileURL else { return }

        if pushHistory, pane.virtualPage == nil, pane.url != url {
            pane.backStack.append(pane.url)
            pane.forwardStack.removeAll()
        }

        pane.virtualPage = nil
        pane.url = url
        pane.entries = []
        pane.selectedIDs.removeAll()
        pane.selectionAnchorID = nil
        pane.selectionCursorID = nil
        pane.renamingID = nil
        if pane.id == .main {
            searchText = ""
        }
        reload(pane)
    }

    func goUp(_ pane: PaneState? = nil) {
        let pane = pane ?? focusedPane
        if pane.virtualPage != nil {
            pane.virtualPage = nil
            reload(pane)
            return
        }
        let parent = pane.url.deletingLastPathComponent()
        guard parent.path != pane.url.path else { return }
        navigate(pane, to: parent)
    }

    func goBack(_ pane: PaneState? = nil) {
        let pane = pane ?? focusedPane
        guard let target = pane.backStack.popLast() else { return }
        pane.forwardStack.append(pane.url)
        navigate(pane, to: target, pushHistory: false)
    }

    func goForward(_ pane: PaneState? = nil) {
        let pane = pane ?? focusedPane
        guard let target = pane.forwardStack.popLast() else { return }
        pane.backStack.append(pane.url)
        navigate(pane, to: target, pushHistory: false)
    }

    func setViewMode(_ mode: ExplorerViewMode, pane: PaneState? = nil) {
        let pane = pane ?? focusedPane
        pane.viewMode = pane.id == .main ? mode : (mode == .preview ? .list : mode)
        persist(pane)
    }

    func setSortField(_ field: SortField, pane: PaneState? = nil) {
        let pane = pane ?? focusedPane
        if pane.sortField == field {
            pane.sortAscending.toggle()
        } else {
            pane.sortField = field
            pane.sortAscending = true
        }
        pane.entries = FileSystemService.sort(pane.entries, by: pane.sortField, ascending: pane.sortAscending)
        persist(pane)
    }

    func setColumnWidth(_ width: CGFloat, for column: FileColumn, in pane: PaneState) {
        pane.setWidth(width, for: column)
        persist(pane)
    }

    func toggleSortDirection(_ pane: PaneState? = nil) {
        let pane = pane ?? focusedPane
        pane.sortAscending.toggle()
        pane.entries = FileSystemService.sort(pane.entries, by: pane.sortField, ascending: pane.sortAscending)
        persist(pane)
    }

    func openSearch() {
        if searchOpen { NativePaneFocus.requestSearch() }
        searchOpen = true
    }

    func closeSearch() {
        searchText = ""
        searchOpen = false
    }

    func select(_ entry: FileEntry, in pane: PaneState, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        focusedPaneID = pane.id
        let displayed = displayedEntries(for: pane)

        if modifiers.contains(.shift), let anchor = pane.selectionAnchorID,
           let anchorIndex = displayed.firstIndex(where: { $0.id == anchor }),
           let targetIndex = displayed.firstIndex(where: { $0.id == entry.id }) {
            let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
            pane.selectedIDs = Set(displayed[range].map(\.id))
            pane.selectionCursorID = entry.id
            return
        }

        if modifiers.contains(.command) || modifiers.contains(.control) {
            if pane.selectedIDs.contains(entry.id) {
                pane.selectedIDs.remove(entry.id)
            } else {
                pane.selectedIDs.insert(entry.id)
            }
            pane.selectionAnchorID = entry.id
            pane.selectionCursorID = entry.id
            return
        }

        pane.selectedIDs = [entry.id]
        pane.selectionAnchorID = entry.id
        pane.selectionCursorID = entry.id
    }

    func primaryClick(_ entry: FileEntry, in pane: PaneState, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        let relevantModifiers = modifiers.intersection([.shift, .command, .control])
        if !relevantModifiers.isEmpty {
            select(entry, in: pane, modifiers: modifiers)
            lastClickedEntryID = nil
            return
        }

        let now = Date()
        let shouldOpen = lastClickedEntryID == entry.id
            && now.timeIntervalSince(lastClickedAt) <= 0.45
        select(entry, in: pane, modifiers: modifiers)
        if shouldOpen {
            lastClickedEntryID = nil
            open(entry, in: pane)
        } else {
            lastClickedEntryID = entry.id
            lastClickedAt = now
        }
    }

    func doubleClick(_ entry: FileEntry, in pane: PaneState) {
        select(entry, in: pane, modifiers: [])
        open(entry, in: pane)
    }

    func selectAllFocused() {
        let pane = focusedPane
        let displayed = displayedEntries(for: pane)
        pane.selectedIDs = Set(displayed.map(\.id))
        pane.selectionAnchorID = displayed.first?.id
        pane.selectionCursorID = displayed.last?.id
    }

    func clearSelection(_ pane: PaneState) {
        pane.selectedIDs.removeAll()
        pane.selectionAnchorID = nil
        pane.selectionCursorID = nil
        focusedPaneID = pane.id
    }

    func clearSelectionIfBlankClick(
        at location: CGPoint,
        frames: [FileEntry.ID: CGRect],
        in pane: PaneState
    ) {
        focusedPaneID = pane.id
        if FileSelectionHitTesting.isBlankLocation(location, frames: frames) {
            clearSelection(pane)
        }
    }

    @discardableResult
    func moveSelection(
        in pane: PaneState? = nil,
        direction: FileSelectionDirection,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) -> Bool {
        let pane = pane ?? focusedPane
        let displayed = displayedEntries(for: pane)
        guard !displayed.isEmpty else { return false }

        focusedPaneID = pane.id
        let step: Int
        switch direction {
        case .left:
            step = -1
        case .right:
            step = 1
        case .up:
            step = -max(1, pane.keyboardColumnCount)
        case .down:
            step = max(1, pane.keyboardColumnCount)
        }

        let currentIndex: Int?
        if let cursor = pane.selectionCursorID,
           let index = displayed.firstIndex(where: { $0.id == cursor }) {
            currentIndex = index
        } else if let selectedIndex = displayed.firstIndex(where: { pane.selectedIDs.contains($0.id) }) {
            currentIndex = selectedIndex
        } else {
            currentIndex = nil
        }

        let targetIndex: Int
        if let currentIndex {
            targetIndex = min(max(currentIndex + step, 0), displayed.count - 1)
        } else {
            targetIndex = step < 0 ? displayed.count - 1 : 0
        }

        let targetID = displayed[targetIndex].id
        if modifiers.intersection(.deviceIndependentFlagsMask).contains(.shift) {
            let anchorID = pane.selectionAnchorID ?? pane.selectionCursorID ?? targetID
            guard let anchorIndex = displayed.firstIndex(where: { $0.id == anchorID }) else {
                pane.selectedIDs = [targetID]
                pane.selectionAnchorID = targetID
                pane.selectionCursorID = targetID
                return true
            }
            let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
            pane.selectedIDs = Set(displayed[range].map(\.id))
            pane.selectionAnchorID = anchorID
            pane.selectionCursorID = targetID
        } else {
            pane.selectedIDs = [targetID]
            pane.selectionAnchorID = targetID
            pane.selectionCursorID = targetID
        }
        return true
    }

    func selectEntries(
        intersecting selectionRect: CGRect,
        frames: [FileEntry.ID: CGRect],
        in pane: PaneState,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) {
        focusedPaneID = pane.id
        let rect = selectionRect.standardized
        let selectedInDisplayOrder = displayedEntries(for: pane).filter { entry in
            guard let frame = frames[entry.id] else { return false }
            return frame.intersects(rect)
        }.map(\.id)

        let additive = modifiers.intersection(.deviceIndependentFlagsMask).contains(.shift)
            || modifiers.intersection(.deviceIndependentFlagsMask).contains(.command)
            || modifiers.intersection(.deviceIndependentFlagsMask).contains(.control)

        if additive {
            pane.selectedIDs.formUnion(selectedInDisplayOrder)
        } else {
            pane.selectedIDs = Set(selectedInDisplayOrder)
        }

        if let first = selectedInDisplayOrder.first {
            pane.selectionAnchorID = first
            pane.selectionCursorID = selectedInDisplayOrder.last
        } else if !additive {
            pane.selectionAnchorID = nil
            pane.selectionCursorID = nil
        }
    }

    func open(_ entry: FileEntry, in pane: PaneState) {
        focusedPaneID = pane.id
        if entry.isDirectory && !entry.isPackage {
            navigate(pane, to: entry.url)
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    func openSelection() {
        let pane = focusedPane
        guard let entry = selectedEntries(in: pane).first else { return }
        open(entry, in: pane)
    }

    func chooseApplicationAndOpen(_ entry: FileEntry, in pane: PaneState) {
        focusedPaneID = pane.id

        let panel = NSOpenPanel()
        panel.title = "选择应用打开"
        panel.prompt = "打开"
        panel.message = "选择用于打开“\(entry.name)”的应用。"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
              let applicationURL = panel.url else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [entry.url],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.showError("打开失败", error)
            }
        }
    }

    func createFolder(in pane: PaneState? = nil) {
        createItem(kind: .folder, in: pane ?? focusedPane)
    }

    func createFile(in pane: PaneState? = nil) {
        createItem(kind: .file, in: pane ?? focusedPane)
    }

    func copySelection(in pane: PaneState? = nil) {
        let pane = pane ?? focusedPane
        let urls = selectedEntries(in: pane).map(\.url)
        guard !urls.isEmpty else { return }
        clipboard = ClipboardPayload(urls: urls, operation: .copy)
        clipboardPasteboardChangeCount = writeFileURLsToSystemPasteboard(urls)
    }

    func cutSelection(in pane: PaneState? = nil) {
        let pane = pane ?? focusedPane
        let urls = selectedEntries(in: pane).map(\.url)
        guard !urls.isEmpty else { return }
        clipboard = ClipboardPayload(urls: urls, operation: .cut)
        clipboardPasteboardChangeCount = writeFileURLsToSystemPasteboard(urls)
    }

    func pasteClipboard(in pane: PaneState? = nil, to targetDirectory: URL? = nil) {
        let pane = pane ?? focusedPane
        guard !isPerformingFileOperation, let clipboard = currentClipboardPayload(), pane.isLocalDirectory else { return }
        let destination = targetDirectory ?? pane.url
        let changeCount = NSPasteboard.general.changeCount
        let request: FileOperationRequest = clipboard.operation == .copy
            ? .copy(clipboard.urls, to: destination) : .move(clipboard.urls, to: destination)
        performFileOperation(request, errorTitle: "粘贴失败") { [weak self] in
            if clipboard.operation == .cut, NSPasteboard.general.changeCount == changeCount {
                guard let self else { return }
                self.clipboard = nil
                self.clipboardPasteboardChangeCount = nil
                NSPasteboard.general.clearContents()
            }
        }
    }

    func trashSelection() {
        let urls = selectedEntries(in: focusedPane).map(\.url)
        guard !urls.isEmpty, !isPerformingFileOperation else { return }
        performFileOperation(.trash(urls), errorTitle: "删除失败")
    }

    private func performFileOperation(
        _ request: FileOperationRequest,
        errorTitle: String,
        onSuccess: @escaping @MainActor () -> Void = {}
    ) {
        guard !isPerformingFileOperation else { return }
        isPerformingFileOperation = true
        fileOperationTask = Task { [weak self, fileOperationWorker] in
            do {
                try await fileOperationWorker.perform(request)
                onSuccess()
            } catch {
                self?.showError(errorTitle, error)
            }
            guard let self else { return }
            self.isPerformingFileOperation = false
            self.reloadAll()
            self.fileOperationTask = nil
        }
    }

    func waitForPendingFileOperations() async {
        await fileOperationTask?.value
        await waitForPendingReloads()
    }

    func beginRenameSelection() {
        let pane = focusedPane
        guard let entry = selectedEntries(in: pane).first, pane.selectedIDs.count == 1 else { return }
        beginRename(entry, in: pane)
    }

    func beginRename(_ entry: FileEntry, in pane: PaneState) {
        guard !isPerformingFileOperation else { return }
        focusedPaneID = pane.id
        pane.renamingID = entry.id
        pane.renameDraft = entry.name
    }

    func commitRename(in pane: PaneState) {
        guard let id = pane.renamingID,
              let entry = pane.entries.first(where: { $0.id == id }) else {
            pane.renamingID = nil
            return
        }

        let newName = pane.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != entry.name else {
            pane.renamingID = nil
            return
        }

        do {
            let newURL = try FileSystemService.rename(entry.url, to: newName)
            pane.renamingID = nil
            reloadAll()
            pane.selectedIDs = [newURL.path]
        } catch {
            showError("重命名失败", error)
        }
    }

    func cancelRename(in pane: PaneState) {
        pane.renamingID = nil
        pane.renameDraft = ""
    }

    func showInfo(for entry: FileEntry) {
        fileInfo = FileInfoSheet(
            entry: entry,
            sizeText: FileSystemService.formattedSize(entry),
            modifiedText: entry.modified.map(DateFormatters.fullDate.string) ?? "--",
            createdText: entry.created.map(DateFormatters.fullDate.string) ?? "--"
        )
    }

    func copyPath(of pane: PaneState) {
        clipboard = nil
        clipboardPasteboardChangeCount = nil
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pane.virtualPage?.title ?? pane.url.path, forType: .string)
    }

    func copyURL(of entry: FileEntry) {
        clipboard = nil
        clipboardPasteboardChangeCount = nil
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.url.path, forType: .string)
    }

    func dragProvider(for entry: FileEntry, in pane: PaneState) -> NSItemProvider {
        if !pane.selectedIDs.contains(entry.id) {
            select(entry, in: pane)
        }

        let draggedURLs = selectedEntries(in: pane).map(\.url)
        let provider = NSItemProvider(item: (draggedURLs.first ?? entry.url) as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let payload = InternalFileDragPayload(
            sourcePaneID: pane.id,
            paths: draggedURLs.map(\.path)
        )
        activeInternalDragPayload = payload
        activeInternalDragExpiresAt = Date().addingTimeInterval(15)
        activeInternalDragProvider = provider
        if let data = try? JSONEncoder().encode(payload) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.xAlgoInternalFileDrag.identifier,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
        }
        return provider
    }

    func dragPasteboardItem(for entry: FileEntry, in pane: PaneState) -> NSPasteboardItem {
        if !pane.selectedIDs.contains(entry.id) {
            select(entry, in: pane)
        }

        let draggedURLs = selectedEntries(in: pane).map(\.url)
        let payload = InternalFileDragPayload(
            sourcePaneID: pane.id,
            paths: draggedURLs.map(\.path)
        )
        activeInternalDragPayload = payload
        activeInternalDragExpiresAt = Date().addingTimeInterval(15)
        activeInternalDragProvider = nil

        let item = NSPasteboardItem()
        item.setString(entry.url.absoluteString, forType: .fileURL)
        item.setString(entry.url.absoluteString, forType: NSPasteboard.PasteboardType(UTType.fileURL.identifier))
        if let data = try? JSONEncoder().encode(payload) {
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.xAlgoInternalFileDrag.identifier))
        }
        return item
    }

    func dropOperation(
        from pasteboard: NSPasteboard,
        into directory: URL,
        intent: FileDropIntent
    ) -> FileDropOperation? {
        if let payload = internalDragPayload(from: pasteboard) {
            return dropOperation(for: payload, into: directory, intent: intent)
        }

        let sourceURLs = Self.fileURLsFromSystemPasteboard(pasteboard)
        guard !sourceURLs.isEmpty else { return nil }
        let operation = Self.preferredDropOperation(
            sourceURLs: sourceURLs,
            into: directory,
            intent: intent
        )
        return canPerformDrop(sourceURLs, into: directory, operation: operation) ? operation : nil
    }

    func handleDrop(
        from pasteboard: NSPasteboard,
        into directory: URL,
        intent: FileDropIntent = .automatic
    ) -> Bool {
        if let payload = internalDragPayload(from: pasteboard) {
            guard let operation = dropOperation(for: payload, into: directory, intent: intent) else {
                clearActiveInternalDrag()
                return false
            }
            performDropped(payload, into: directory, operation: operation)
            clearActiveInternalDrag()
            return true
        }

        clearActiveInternalDrag()

        let sourceURLs = Self.fileURLsFromSystemPasteboard(pasteboard)
        guard !sourceURLs.isEmpty,
              dropOperation(from: pasteboard, into: directory, intent: intent) != nil else { return false }
        performDropped(sourceURLs, into: directory, intent: intent)
        return true
    }

    func handleDrop(
        _ providers: [NSItemProvider],
        into directory: URL,
        intent: FileDropIntent = .automatic
    ) -> Bool {
        guard directory.isFileURL else { return false }

        let internalDragProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.xAlgoInternalFileDrag.identifier)
        }
        if !internalDragProviders.isEmpty {
            if let activePayload = freshActiveInternalDragPayload(matching: internalDragProviders) {
                guard let operation = dropOperation(for: activePayload, into: directory, intent: intent) else {
                    clearActiveInternalDrag()
                    return false
                }
                performDropped(activePayload, into: directory, operation: operation)
                clearActiveInternalDrag()
                return true
            }

            for provider in internalDragProviders {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.xAlgoInternalFileDrag.identifier) { [weak self] data, error in
                    guard error == nil,
                          let data,
                          let payload = try? JSONDecoder().decode(InternalFileDragPayload.self, from: data) else {
                        return
                    }
                    Task { @MainActor in
                        guard let self,
                              let operation = self.dropOperation(for: payload, into: directory, intent: intent) else {
                            return
                        }
                        self.performDropped(payload, into: directory, operation: operation)
                        self.clearActiveInternalDrag()
                    }
                }
            }
            return true
        }

        clearActiveInternalDrag()

        let fileURLProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileURLProviders.isEmpty else { return false }

        for provider in fileURLProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                guard error == nil, let sourceURL = Self.fileURL(from: item) else {
                    return
                }
                Task { @MainActor in
                    self?.performDropped([sourceURL], into: directory, intent: intent)
                }
            }
        }
        return true
    }

    func navigateToDroppedDirectory(
        _ providers: [NSItemProvider],
        in pane: PaneState
    ) -> Bool {
        let internalDragProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.xAlgoInternalFileDrag.identifier)
        }
        if !internalDragProviders.isEmpty {
            if let activePayload = freshActiveInternalDragPayload(matching: internalDragProviders) {
                clearActiveInternalDrag()
                return navigateToDroppedDirectory(sourceURLs(from: activePayload), in: pane)
            }

            for provider in internalDragProviders {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.xAlgoInternalFileDrag.identifier) { [weak self] data, error in
                    guard error == nil,
                          let data,
                          let payload = try? JSONDecoder().decode(InternalFileDragPayload.self, from: data) else {
                        return
                    }
                    Task { @MainActor in
                        guard let self else { return }
                        _ = self.navigateToDroppedDirectory(self.sourceURLs(from: payload), in: pane)
                    }
                }
            }
            return true
        }

        clearActiveInternalDrag()

        let fileURLProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileURLProviders.isEmpty else { return false }

        for provider in fileURLProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                guard error == nil, let sourceURL = Self.fileURL(from: item) else {
                    return
                }
                Task { @MainActor in
                    _ = self?.navigateToDroppedDirectory([sourceURL], in: pane)
                }
            }
        }
        return true
    }

    var hasActiveInternalDrag: Bool {
        freshActiveInternalDragPayload() != nil
    }

    func canDropActiveInternalDrag(into directory: URL) -> Bool {
        activeInternalDropOperation(into: directory, intent: .automatic) != nil
    }

    func canNavigateActiveInternalDragToDirectory() -> Bool {
        guard let payload = freshActiveInternalDragPayload() else { return false }
        return droppedDirectoryURL(from: sourceURLs(from: payload)) != nil
    }

    func activeInternalDropOperation(
        into directory: URL,
        intent: FileDropIntent
    ) -> FileDropOperation? {
        guard let payload = freshActiveInternalDragPayload() else { return nil }
        return dropOperation(for: payload, into: directory, intent: intent)
    }

    static func preferredDropOperation(
        sourceURLs: [URL],
        into directory: URL,
        intent: FileDropIntent,
        sameVolume: (URL, URL) -> Bool = FileSystemService.areOnSameVolume
    ) -> FileDropOperation {
        switch intent {
        case .forceCopy:
            return .copy
        case .forceMove:
            return .move
        case .automatic:
            return sourceURLs.allSatisfy { sameVolume($0, directory) } ? .move : .copy
        }
    }

    func handleSidebarShortcutDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileURLProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileURLProviders.isEmpty else { return false }

        for provider in fileURLProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                guard error == nil, let shortcutURL = Self.fileURL(from: item) else {
                    return
                }
                Task { @MainActor in
                    self?.addSidebarShortcut(shortcutURL)
                }
            }
        }
        return true
    }

    func addSidebarShortcuts(_ urls: [URL]) -> Bool {
        var didAddShortcut = false
        for url in urls {
            if addSidebarShortcut(url) {
                didAddShortcut = true
            }
        }
        return didAddShortcut
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 53, searchOpen {
            closeSearch()
            NativePaneFocus.request(focusedPaneID)
            return true
        }

        if NSApp.keyWindow?.firstResponder is NSTextView {
            return false
        }

        switch (event.keyCode, flags) {
        case (0, let flags) where flags.contains(.command): // A
            selectAllFocused()
            return true
        case (3, let flags) where flags.contains(.command): // F
            openSearch()
            return true
        case (36, _): // Return
            openSelection()
            return true
        case (51, _): // Backspace/Delete key on compact keyboards.
            if hasSelection {
                trashSelection()
            } else {
                goUp()
            }
            return true
        case (117, _): // Forward delete.
            trashSelection()
            return true
        case (123, let flags) where flags.contains(.option):
            goBack()
            return true
        case (124, let flags) where flags.contains(.option):
            goForward()
            return true
        case (126, let flags) where flags.contains(.option):
            goUp()
            return true
        case (123, let flags) where flags.isSelectionMove:
            return moveSelection(direction: .left, modifiers: flags)
        case (124, let flags) where flags.isSelectionMove:
            return moveSelection(direction: .right, modifiers: flags)
        case (125, let flags) where flags.isSelectionMove:
            return moveSelection(direction: .down, modifiers: flags)
        case (126, let flags) where flags.isSelectionMove:
            return moveSelection(direction: .up, modifiers: flags)
        case (120, _): // F2
            beginRenameSelection()
            return true
        case (96, _): // F5
            refreshFocusedPane()
            return true
        default:
            return false
        }
    }

    func selectedEntries(in pane: PaneState) -> [FileEntry] {
        pane.entries.filter { pane.selectedIDs.contains($0.id) }
    }

    func updateKeyboardColumnCount(_ count: Int, in pane: PaneState) {
        pane.keyboardColumnCount = max(1, count)
    }

    private enum NewItemKind {
        case folder
        case file
    }

    private func createItem(kind: NewItemKind, in pane: PaneState) {
        guard pane.isLocalDirectory, !isPerformingFileOperation else { return }
        do {
            let url: URL
            switch kind {
            case .folder:
                url = try FileSystemService.createFolder(in: pane.url)
            case .file:
                url = try FileSystemService.createFile(in: pane.url)
            }
            reload(pane)
            pane.selectedIDs = [url.path]
            pane.selectionCursorID = url.path
            pane.renamingID = url.path
            pane.renameDraft = url.lastPathComponent
        } catch {
            showError("新建失败", error)
        }
    }

    private func showError(_ title: String, _ error: Error) {
        self.error = ExplorerError(title: title, message: error.localizedDescription)
    }

    private func currentClipboardPayload() -> ClipboardPayload? {
        if let clipboard,
           clipboardPasteboardChangeCount == NSPasteboard.general.changeCount {
            return clipboard
        }

        let urls = Self.fileURLsFromSystemPasteboard()
        guard !urls.isEmpty else { return nil }
        return ClipboardPayload(urls: urls, operation: .copy)
    }

    @discardableResult
    private func writeFileURLsToSystemPasteboard(_ urls: [URL]) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        return pasteboard.changeCount
    }

    @discardableResult
    private func addSidebarShortcut(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let standardizedURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else { return false }

        sidebarShortcutURLs.removeAll { $0.standardizedFileURL == standardizedURL }
        sidebarShortcutURLs.append(standardizedURL)
        persistSidebarShortcuts()
        return true
    }

    private func persistSidebarShortcuts() {
        defaults.set(sidebarShortcutURLs.map(\.path), forKey: Self.sidebarShortcutPathsKey)
    }

    private func persistHiddenDefaultSidebarTargets() {
        defaults.set(Array(hiddenDefaultSidebarTargetIDs), forKey: Self.hiddenDefaultSidebarTargetIDsKey)
    }

    private static func storedSidebarShortcutURLs() -> [URL] {
        UserDefaults.standard
            .stringArray(forKey: sidebarShortcutPathsKey)?
            .map { URL(fileURLWithPath: $0).standardizedFileURL } ?? []
    }

    private static func storedHiddenDefaultSidebarTargetIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: hiddenDefaultSidebarTargetIDsKey) ?? [])
    }

    private func sidebarShortcutSymbol(for url: URL) -> String {
        if isDirectory(url) {
            return "folder"
        }

        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return "doc"
        }
        if contentType.conforms(to: .image) {
            return "photo"
        }
        if contentType.conforms(to: .movie) {
            return "play.rectangle"
        }
        if contentType.conforms(to: .audio) {
            return "music.note"
        }
        if contentType.conforms(to: .text) {
            return "doc.text"
        }
        return "doc"
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func dropOperation(
        for payload: InternalFileDragPayload,
        into directory: URL,
        intent: FileDropIntent
    ) -> FileDropOperation? {
        let sourceURLs = sourceURLs(from: payload)
        guard !sourceURLs.isEmpty else { return nil }

        let operation = Self.preferredDropOperation(
            sourceURLs: sourceURLs,
            into: directory,
            intent: intent
        )
        return canPerformDrop(sourceURLs, into: directory, operation: operation) ? operation : nil
    }

    private func performDropped(
        _ payload: InternalFileDragPayload,
        into directory: URL,
        operation: FileDropOperation
    ) {
        performDropped(sourceURLs(from: payload), into: directory, operation: operation)
    }

    @discardableResult
    private func navigateToDroppedDirectory(
        _ sourceURLs: [URL],
        in pane: PaneState
    ) -> Bool {
        guard let directoryURL = droppedDirectoryURL(from: sourceURLs) else { return false }
        focusedPaneID = pane.id
        navigate(pane, to: directoryURL)
        return true
    }

    private func droppedDirectoryURL(from sourceURLs: [URL]) -> URL? {
        guard sourceURLs.count == 1,
              let sourceURL = sourceURLs.first?.standardizedFileURL,
              isDirectory(sourceURL) else {
            return nil
        }
        return sourceURL
    }

    private func performDropped(
        _ sourceURLs: [URL],
        into directory: URL,
        intent: FileDropIntent
    ) {
        let operation = Self.preferredDropOperation(
            sourceURLs: sourceURLs,
            into: directory,
            intent: intent
        )
        performDropped(sourceURLs, into: directory, operation: operation)
    }

    private func performDropped(
        _ sourceURLs: [URL],
        into directory: URL,
        operation: FileDropOperation
    ) {
        let sourceURLs = sourceURLs
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .filter {
                switch operation {
                case .copy:
                    return canCopyDroppedItem($0, into: directory)
                case .move:
                    return canMoveDroppedItem($0, into: directory)
                }
            }

        guard !sourceURLs.isEmpty else { return }

        let request: FileOperationRequest = operation == .copy
            ? .copy(sourceURLs, to: directory) : .move(sourceURLs, to: directory)
        performFileOperation(request, errorTitle: "拖放失败")
    }

    private func canPerformDrop(
        _ sourceURLs: [URL],
        into directory: URL,
        operation: FileDropOperation
    ) -> Bool {
        guard !isPerformingFileOperation else { return false }
        return sourceURLs.contains {
            switch operation {
            case .copy:
                return canCopyDroppedItem($0, into: directory)
            case .move:
                return canMoveDroppedItem($0, into: directory)
            }
        }
    }

    private func freshActiveInternalDragPayload(
        matching providers: [NSItemProvider]? = nil
    ) -> InternalFileDragPayload? {
        guard let payload = activeInternalDragPayload,
              let expiresAt = activeInternalDragExpiresAt else {
            return nil
        }
        if let providers {
            guard let activeInternalDragProvider,
                  providers.contains(where: { $0 === activeInternalDragProvider }) else {
                return nil
            }
        }
        if expiresAt < Date() {
            clearActiveInternalDrag()
            return nil
        }
        return payload
    }

    private func clearActiveInternalDrag() {
        activeInternalDragPayload = nil
        activeInternalDragExpiresAt = nil
        activeInternalDragProvider = nil
    }

    private func internalDragPayload(from pasteboard: NSPasteboard) -> InternalFileDragPayload? {
        let internalType = NSPasteboard.PasteboardType(UTType.xAlgoInternalFileDrag.identifier)
        if let data = pasteboard.data(forType: internalType),
           let payload = try? JSONDecoder().decode(InternalFileDragPayload.self, from: data) {
            return payload
        }
        return nil
    }

    private func sourceURLs(from payload: InternalFileDragPayload) -> [URL] {
        payload.paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func canMoveDroppedItem(_ sourceURL: URL, into directory: URL) -> Bool {
        let source = sourceURL.standardizedFileURL
        let destination = directory.standardizedFileURL
        guard source != destination else { return false }
        guard source.deletingLastPathComponent() != destination else { return false }
        return canDropSource(source, into: destination)
    }

    private func canCopyDroppedItem(_ sourceURL: URL, into directory: URL) -> Bool {
        let source = sourceURL.standardizedFileURL
        let destination = directory.standardizedFileURL
        guard source != destination else { return false }
        return canDropSource(source, into: destination)
    }

    private func canDropSource(_ source: URL, into destination: URL) -> Bool {
        if isDirectory(source) {
            let sourcePath = source.path.hasSuffix("/") ? source.path : source.path + "/"
            let destinationPath = destination.path.hasSuffix("/") ? destination.path : destination.path + "/"
            guard !destinationPath.hasPrefix(sourcePath) else { return false }
        }

        return true
    }

    nonisolated private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return normalizedFileURL(url)
        }
        if let url = item as? NSURL {
            return normalizedFileURL(url as URL)
        }
        if let data = item as? Data {
            if let string = String(data: data, encoding: .utf8),
               let url = fileURL(fromPasteboardString: string) {
                return url
            }
            return normalizedFileURL(URL(dataRepresentation: data, relativeTo: nil))
        }
        if let string = item as? String {
            return fileURL(fromPasteboardString: string)
        }
        return nil
    }

    nonisolated private static func fileURLsFromSystemPasteboard(_ pasteboard: NSPasteboard = .general) -> [URL] {
        var urls: [URL] = []

        if let nsURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] {
            urls.append(contentsOf: nsURLs.compactMap { normalizedFileURL($0 as URL) })
        }

        if let fileURLString = pasteboard.string(forType: .fileURL),
           let url = fileURL(fromPasteboardString: fileURLString) {
            urls.append(url)
        }

        var seen: Set<String> = []
        return urls
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .filter { seen.insert($0.path).inserted }
    }

    nonisolated private static func fileURL(fromPasteboardString string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }

        guard let url = URL(string: trimmed) else { return nil }
        return normalizedFileURL(url)
    }

    nonisolated private static func normalizedFileURL(_ url: URL?) -> URL? {
        guard let url, url.isFileURL, !url.path.isEmpty else { return nil }
        return url.standardizedFileURL
    }

    private func persist(_ pane: PaneState) {
        defaults.set(pane.url.path, forKey: "\(pane.id.rawValue)Path")
        defaults.set(pane.viewMode.rawValue, forKey: "\(pane.id.rawValue)ViewMode")
        defaults.set(pane.sortField.rawValue, forKey: "\(pane.id.rawValue)SortField")
        defaults.set(pane.sortAscending, forKey: "\(pane.id.rawValue)SortAscending")
        for column in FileColumn.allCases {
            defaults.set(Double(pane.width(for: column)), forKey: columnWidthKey(pane, column))
        }
    }

    private func applyStoredColumnWidths(_ pane: PaneState) {
        for column in FileColumn.allCases {
            guard let value = defaults.object(forKey: columnWidthKey(pane, column)) as? Double else {
                continue
            }
            pane.setWidth(CGFloat(value), for: column)
        }
    }

    private func columnWidthKey(_ pane: PaneState, _ column: FileColumn) -> String {
        "\(pane.id.rawValue)ColumnWidth.\(column.rawValue)"
    }

    private static func storedURL(_ key: String) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private static func storedViewMode(_ key: String) -> ExplorerViewMode? {
        guard let raw = UserDefaults.standard.string(forKey: key) else {
            return nil
        }
        return ExplorerViewMode(rawValue: raw)
    }

    private static func storedSortField(_ key: String) -> SortField? {
        guard let raw = UserDefaults.standard.string(forKey: key) else {
            return nil
        }
        return SortField(rawValue: raw)
    }
}

enum FileSelectionHitTesting {
    static func isBlankLocation(
        _ location: CGPoint,
        frames: [FileEntry.ID: CGRect]
    ) -> Bool {
        !frames.values.contains { $0.contains(location) }
    }
}

private extension NSEvent.ModifierFlags {
    var isSelectionMove: Bool {
        let flags = intersection(.deviceIndependentFlagsMask)
        return !flags.contains(.option)
            && !flags.contains(.command)
            && !flags.contains(.control)
    }
}

@MainActor
final class ThumbnailCache: ObservableObject {
    @Published private(set) var revision = 0
    private let images = NSCache<NSString, NSImage>()
    private var requested: Set<String> = []

    init() {
        images.countLimit = 256
        images.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for url: URL) -> NSImage? {
        images.object(forKey: url.path as NSString)
    }

    func request(url: URL, size: CGSize) {
        let key = url.path
        guard images.object(forKey: key as NSString) == nil, !requested.contains(key) else { return }
        requested.insert(key)

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            let image = thumbnail?.nsImage
            Task { @MainActor in
                guard let self else { return }
                self.requested.remove(key)
                guard let image else { return }
                self.images.setObject(image, forKey: key as NSString, cost: Int(size.width * size.height * 16))
                self.revision += 1
            }
        }
    }
}
