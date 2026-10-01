import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FilePaneRole {
    case main
    case assist
}

struct DirectoryNavigationDropDelegate: DropDelegate {
    static let acceptedTypes: [UTType] = [.xAlgoInternalFileDrag, .fileURL]

    let model: ExplorerModel
    let pane: PaneState
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        if model.hasActiveInternalDrag {
            return model.canNavigateActiveInternalDragToDirectory()
        }
        return info.hasItemsConforming(to: Self.acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        validateDrop(info: info)
            ? DropProposal(operation: .copy)
            : DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard validateDrop(info: info) else { return false }
        return model.navigateToDroppedDirectory(
            info.itemProviders(for: Self.acceptedTypes),
            in: pane
        )
    }
}

struct FilePaneView: View {
    @EnvironmentObject private var model: ExplorerModel
    @ObservedObject var pane: PaneState
    let role: FilePaneRole

    var body: some View {
        VStack(spacing: 0) {
            if role == .assist {
                AssistPaneHeaderView(pane: pane)
            } else {
                NativeGlassContainer {
                    HStack(spacing: 10) {
                        CapsuleGroup {
                            SortMenuView(pane: pane)
                            ViewModeMenuView(pane: pane)
                        }
                        MainPathView(path: pane.title) { model.copyPath(of: pane) }
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()
            if pane.virtualPage == .network {
                NetworkPaneView()
            } else {
                fileArea
                    .overlay {
                        if pane.isLoading && pane.entries.isEmpty {
                            ProgressView().controlSize(.small).allowsHitTesting(false)
                        } else if let error = pane.errorMessage {
                            EmptyStateView(symbolName: "exclamationmark.triangle", title: error)
                                .padding(24)
                                .allowsHitTesting(false)
                        } else if model.displayedEntries(for: pane).isEmpty {
                            EmptyStateView(symbolName: "folder", title: model.commandText(
                                model.searchText.isEmpty ? .emptyFolder : .noSearchResults
                            ))
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .top) {
            if model.assistOpen && model.focusedPaneID == pane.id {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(height: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var fileArea: some View {
        switch pane.viewMode {
        case .list:
            AppKitTablePaneView(pane: pane, role: role)
        case .files, .preview:
            AppKitCollectionPaneView(pane: pane, role: role, previewStyle: pane.viewMode == .preview && pane.id == .main)
        }
    }
}

struct AssistPaneHeaderView: View {
    @EnvironmentObject private var model: ExplorerModel
    @ObservedObject var pane: PaneState
    @State private var isDirectoryDropTarget = false

    var body: some View {
        NativeGlassContainer {
            HStack(spacing: 6) {
                CapsuleGroup {
                    CommandIconButton(model.text(.tooltipGoUp), systemName: "chevron.up") { model.goUp(pane) }
                        .disabled(!pane.canGoUp)
                    CommandIconButton(model.text(.tooltipBack), systemName: "chevron.left") { model.goBack(pane) }
                        .disabled(!pane.canGoBack)
                    CommandIconButton(model.text(.tooltipForward), systemName: "chevron.right") { model.goForward(pane) }
                        .disabled(!pane.canGoForward)
                }
                Text(pane.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .frame(height: 36)
                    .background(isDirectoryDropTarget ? Color.selectedCapsule : .clear, in: Capsule())
                    .help(pane.url.path + "\n" + model.text(.tooltipCopyPath))
                    .onTapGesture(count: 2) { model.copyPath(of: pane) }
                    .onDrop(
                        of: DirectoryNavigationDropDelegate.acceptedTypes,
                        delegate: DirectoryNavigationDropDelegate(
                            model: model, pane: pane, isTargeted: $isDirectoryDropTarget
                        )
                    )
                CapsuleGroup {
                    SortMenuView(pane: pane)
                    ViewModeMenuView(pane: pane)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

enum FileContextMenuLayout {
    static let chooseApplicationOpenTitle = "选择应用打开"
    static let copyURLTitle = "复制URL"
    static let topActionTitles = [chooseApplicationOpenTitle, copyURLTitle]
}

struct NetworkPaneView: View {
    @EnvironmentObject private var model: ExplorerModel

    var body: some View {
        ContentUnavailableView {
            Label(model.text(.sidebarNetwork), systemImage: "network")
        } description: {
            Text(model.commandText(.noNetworkDevices))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum NetworkDiscovery {
    static func discoveredDeviceNames() -> [String] { [] }
}

struct EmptyStateView: View {
    let symbolName: String
    let title: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbolName)
        }
    }
}
