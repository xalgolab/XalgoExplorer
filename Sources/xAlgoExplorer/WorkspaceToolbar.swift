import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CommandSurfaceView: View {
    @EnvironmentObject private var model: ExplorerModel

    var body: some View {
        NativeGlassContainer {
            HStack(spacing: 12) {
                MainNavigationControls(pane: model.mainPane)
                FocusedFileControls(pane: model.focusedPane)
                if model.isPerformingFileOperation {
                    ProgressView().controlSize(.small).frame(width: 18)
                }
                Spacer(minLength: 8)
                if model.searchOpen {
                    NativeSearchField(
                        text: $model.searchText,
                        placeholder: model.text(.tooltipSearch),
                        onClose: closeSearch,
                        onSubmit: { NativePaneFocus.request(model.focusedPaneID) }
                    )
                    .frame(minWidth: 160, idealWidth: 220, maxWidth: 280, minHeight: 30)
                    CommandIconButton(model.commandText(.closeSearch), systemName: "xmark") { closeSearch() }
                } else {
                    CapsuleGroup {
                        CommandIconButton(model.text(.tooltipSearch), systemName: "magnifyingglass") {
                            model.openSearch()
                        }
                    }
                }
                CapsuleGroup {
                    NativeSymbolButton(
                        title: model.text(.tooltipThreePane),
                        symbol: "rectangle.split.3x1",
                        isSelected: model.assistOpen
                    ) {
                        model.toggleAssist()
                        NativePaneFocus.request(model.focusedPaneID)
                    }
                    .frame(width: 32, height: 30)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func closeSearch() {
        model.closeSearch()
        NativePaneFocus.request(model.focusedPaneID)
    }
}

private struct MainNavigationControls: View {
    @EnvironmentObject private var model: ExplorerModel
    @ObservedObject var pane: PaneState

    var body: some View {
        CapsuleGroup {
            CommandIconButton(model.text(.tooltipGoUp), systemName: "chevron.up") { model.goUp(pane) }
                .disabled(!pane.canGoUp)
            CommandIconButton(model.text(.tooltipBack), systemName: "chevron.left") { model.goBack(pane) }
                .disabled(!pane.canGoBack)
            CommandIconButton(model.text(.tooltipForward), systemName: "chevron.right") { model.goForward(pane) }
                .disabled(!pane.canGoForward)
            CommandIconButton(model.text(.tooltipRefresh), systemName: "arrow.clockwise") { model.reload(pane) }
        }
    }
}

private struct FocusedFileControls: View {
    @EnvironmentObject private var model: ExplorerModel
    @ObservedObject var pane: PaneState

    var body: some View {
        CapsuleGroup {
            CommandIconButton(model.text(.tooltipCreateFolder), systemName: "folder.badge.plus") { model.createFolder() }
                .disabled(!pane.isLocalDirectory || model.isPerformingFileOperation)
            CommandIconButton(model.text(.tooltipCreateFile), systemName: "doc.badge.plus") { model.createFile() }
                .disabled(!pane.isLocalDirectory || model.isPerformingFileOperation)
            CommandIconButton(model.text(.tooltipCut), systemName: "scissors") { model.cutSelection() }
                .disabled(pane.selectedIDs.isEmpty)
            CommandIconButton(model.text(.tooltipCopy), systemName: "doc.on.doc") { model.copySelection() }
                .disabled(pane.selectedIDs.isEmpty)
            CommandIconButton(model.text(.tooltipPaste), systemName: "doc.on.clipboard") { model.pasteClipboard() }
                .disabled(!model.canPaste(in: pane))
        }
    }
}

struct MainPathView: View {
    @EnvironmentObject private var model: ExplorerModel
    let path: String
    let copyAction: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(path)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .capsuleSurface()
        .help(path + "\n" + model.text(.tooltipCopyPath))
        .accessibilityLabel(path)
        .onTapGesture(count: 2, perform: copyAction)
        .contextMenu {
            Button(model.text(.tooltipCopy)) { copyAction() }
        }
    }
}

struct CapsuleGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .frame(height: 36)
        .padding(.horizontal, 4)
        .fixedSize(horizontal: true, vertical: false)
        .capsuleSurface()
    }
}

struct CommandIconButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    init(_ title: String, systemName: String, action: @escaping () -> Void) {
        self.title = title
        self.systemName = systemName
        self.action = action
    }

    var body: some View {
        NativeSymbolButton(title: title, symbol: systemName, action: action)
            .frame(width: 32, height: 30)
    }
}

struct SortMenuView: View {
    @EnvironmentObject private var model: ExplorerModel
    @ObservedObject var pane: PaneState

    var body: some View {
        Menu {
            ForEach(SortField.allCases) { field in
                Button {
                    model.setSortField(field, pane: pane)
                } label: {
                    HStack {
                        Text(NativeCommandText.sortField(field, language: model.language))
                        if pane.sortField == field {
                            Text(pane.sortAscending ? "↑" : "↓")
                        }
                    }
                }
            }
        } label: {
            MenuIconLabel(systemName: "line.3.horizontal.decrease", width: pane.id.isAssist ? 28 : 34)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(model.text(.tooltipSort))
    }
}

struct ViewModeMenuView: View {
    @EnvironmentObject private var model: ExplorerModel
    @ObservedObject var pane: PaneState

    var body: some View {
        Menu {
            ForEach(pane.id == .main ? ExplorerViewMode.allCases : [.list, .files]) { mode in
                Button {
                    model.setViewMode(mode, pane: pane)
                } label: {
                    Label(NativeCommandText.viewMode(mode, language: model.language), systemImage: mode.symbolName)
                }
            }
        } label: {
            MenuIconLabel(systemName: pane.viewMode.symbolName, width: pane.id.isAssist ? 28 : 34)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(model.text(.tooltipView))
    }
}

private struct MenuIconLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    let systemName: String
    let width: CGFloat

    var body: some View {
        HStack(spacing: width <= 38 ? 4 : 6) {
            Image(systemName: systemName)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .frame(width: width, height: 30)
        .foregroundStyle(isEnabled ? .primary : .secondary)
        .background(
            Capsule()
                .fill(isEnabled && isHovering ? Color.rowHover : .clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
