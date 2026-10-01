import AppKit
import Foundation
import UniformTypeIdentifiers

enum PaneID: String, CaseIterable, Identifiable, Codable {
    case main
    case assistTop
    case assistBottom

    var id: String { rawValue }

    var isAssist: Bool {
        self != .main
    }
}

extension UTType {
    static let xAlgoInternalFileDrag = UTType(exportedAs: "com.xalgo.explorer.internal-file-drag")
}

struct InternalFileDragPayload: Codable {
    let sourcePaneID: PaneID
    let paths: [String]
}

enum FileDropIntent: Equatable {
    case automatic
    case forceCopy
    case forceMove

    init(modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            self = .forceMove
        } else if flags.contains(.control) {
            self = .forceCopy
        } else {
            self = .automatic
        }
    }
}

enum FileDropOperation: Equatable {
    case copy
    case move
}

enum FileSelectionDirection {
    case up
    case down
    case left
    case right
}

enum ExplorerViewMode: String, CaseIterable, Identifiable, Codable {
    case list
    case files
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "列表"
        case .files: "文件"
        case .preview: "预览"
        }
    }

    var symbolName: String {
        switch self {
        case .list: "list.bullet"
        case .files: "square.grid.3x3"
        case .preview: "rectangle.grid.2x2"
        }
    }
}

enum SortField: String, CaseIterable, Identifiable, Codable {
    case name
    case modified
    case created
    case size
    case type
    case ext

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "名称"
        case .modified: "修改时间"
        case .created: "创建时间"
        case .size: "大小"
        case .type: "类型"
        case .ext: "扩展名"
        }
    }

    var columnTitle: String {
        switch self {
        case .name: "文件名"
        case .modified: "修改日期"
        case .created: "创建日期"
        case .size: "大小"
        case .type: "类型"
        case .ext: "扩展名"
        }
    }
}

enum FileColumn: String, CaseIterable, Identifiable {
    case name
    case modified
    case type
    case size

    var id: String { rawValue }

    var minWidth: CGFloat {
        switch self {
        case .name: 120
        case .modified: 78
        case .type: 58
        case .size: 58
        }
    }

    func defaultWidth(for paneID: PaneID) -> CGFloat {
        switch (paneID, self) {
        case (_, .name):
            paneID == .main ? 320 : 176
        case (_, .modified):
            paneID == .main ? 146 : 92
        case (_, .type):
            paneID == .main ? 92 : 64
        case (_, .size):
            paneID == .main ? 90 : 64
        }
    }
}

enum VirtualPage: String, Codable {
    case network

    var title: String {
        switch self {
        case .network: "内网计算机"
        }
    }
}

struct FileEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let modified: Date?
    let created: Date?
    let size: Int64?
    let typeDescription: String
    let typeIdentifier: String?

    var id: String { url.path }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }
}

struct SidebarTarget: Identifiable, Hashable {
    enum Kind: Hashable {
        case folder(URL)
        case file(URL)
        case network
    }

    enum Group: Hashable {
        case appDefault
        case userShortcut
        case mountedVolume
        case utility
    }

    let id: String
    let title: String
    let symbolName: String
    let kind: Kind
    let group: Group

    var isUserShortcut: Bool {
        group == .userShortcut
    }

    init(
        id: String,
        title: String,
        symbolName: String,
        kind: Kind,
        group: Group = .utility
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.kind = kind
        self.group = group
    }
}

struct ClipboardPayload {
    enum Operation {
        case copy
        case cut
    }

    let urls: [URL]
    let operation: Operation
}

struct ExplorerError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct FileInfoSheet: Identifiable {
    let id = UUID()
    let entry: FileEntry
    let sizeText: String
    let modifiedText: String
    let createdText: String
}

@MainActor
final class PaneState: ObservableObject, Identifiable {
    let id: PaneID
    @Published var url: URL
    @Published var virtualPage: VirtualPage?
    @Published var entries: [FileEntry] = []
    @Published var selectedIDs: Set<FileEntry.ID> = []
    @Published var viewMode: ExplorerViewMode
    @Published var sortField: SortField
    @Published var sortAscending: Bool
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var renamingID: FileEntry.ID?
    @Published var renameDraft = ""
    @Published var columnNameWidth: CGFloat
    @Published var columnModifiedWidth: CGFloat
    @Published var columnTypeWidth: CGFloat
    @Published var columnSizeWidth: CGFloat

    @Published var backStack: [URL] = []
    @Published var forwardStack: [URL] = []
    var selectionAnchorID: FileEntry.ID?
    var selectionCursorID: FileEntry.ID?
    var keyboardColumnCount = 1

    init(
        id: PaneID,
        url: URL,
        viewMode: ExplorerViewMode = .list,
        sortField: SortField = .name,
        sortAscending: Bool = true
    ) {
        self.id = id
        self.url = url
        self.viewMode = id == .main ? viewMode : (viewMode == .preview ? .list : viewMode)
        self.sortField = sortField
        self.sortAscending = sortAscending
        self.columnNameWidth = FileColumn.name.defaultWidth(for: id)
        self.columnModifiedWidth = FileColumn.modified.defaultWidth(for: id)
        self.columnTypeWidth = FileColumn.type.defaultWidth(for: id)
        self.columnSizeWidth = FileColumn.size.defaultWidth(for: id)
    }

    var title: String {
        if let virtualPage {
            return virtualPage.title
        }
        if id == .main {
            return url.path
        }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    var canGoBack: Bool {
        !backStack.isEmpty
    }

    var canGoForward: Bool {
        !forwardStack.isEmpty
    }

    var isLocalDirectory: Bool {
        virtualPage == nil
    }

    var canGoUp: Bool {
        if virtualPage != nil {
            return true
        }
        return url.deletingLastPathComponent().path != url.path
    }

    var totalColumnWidth: CGFloat {
        columnNameWidth + columnModifiedWidth + columnTypeWidth + columnSizeWidth
    }

    func width(for column: FileColumn) -> CGFloat {
        switch column {
        case .name: columnNameWidth
        case .modified: columnModifiedWidth
        case .type: columnTypeWidth
        case .size: columnSizeWidth
        }
    }

    func setWidth(_ width: CGFloat, for column: FileColumn) {
        let clamped = max(column.minWidth, width)
        switch column {
        case .name:
            columnNameWidth = clamped
        case .modified:
            columnModifiedWidth = clamped
        case .type:
            columnTypeWidth = clamped
        case .size:
            columnSizeWidth = clamped
        }
    }
}
