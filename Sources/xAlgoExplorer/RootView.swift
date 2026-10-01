import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: ExplorerModel
    @State private var railPeekOpen = false

    var body: some View {
        WorkspaceView(railPeekOpen: $railPeekOpen)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(WindowConfigurator { event in
            if NativePaneFocus.isFileArea(NSApp.keyWindow?.firstResponder) {
                return false
            }
            return model.handleKeyDown(event)
        })
        .alert(item: $model.error) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("确定"))
            )
        }
        .sheet(item: $model.fileInfo) { info in
            FileInfoView(info: info)
        }
        .sheet(isPresented: $model.showingAbout) {
            AboutView()
        }
    }
}

struct WorkspaceView: View {
    @EnvironmentObject private var model: ExplorerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var railPeekOpen: Bool
    @State private var railBodyHovering = false
    @State private var railTriggerHovering = false
    @State private var railDropTarget = false
    @State private var closeTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let height = min(
                RailPeekLayout.railContentHeight(
                    defaultCount: model.defaultSidebarTargets.count,
                    userCount: model.userSidebarTargets.count,
                    utilityCount: model.utilitySidebarTargets.count
                ),
                max(0, geometry.size.height - 24)
            )

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if !model.hideRail && !model.assistOpen {
                        RailView(maxHeight: height)
                            .padding(.horizontal, 6)
                            .frame(width: RailPeekLayout.dockedRailSlotWidth + 12)
                            .frame(maxHeight: .infinity)
                    }
                    ExplorerShellView()
                }

                if !model.hideRail && model.assistOpen {
                    ZStack(alignment: .leading) {
                        RailView(maxHeight: height)
                            .offset(x: RailPeekLayout.railOffset(isOpen: railPeekOpen))
                            .onHover {
                                railBodyHovering = $0
                                updateRailVisibility()
                            }

                        if !railPeekOpen {
                            CollapsedRailStripView(height: height)
                                .allowsHitTesting(false)
                        }

                        RailPeekTriggerView(
                            width: RailPeekLayout.triggerWidth(isDropTarget: railDropTarget),
                            height: height,
                            isDropTarget: $railDropTarget,
                            onHover: {
                                railTriggerHovering = $0
                                updateRailVisibility()
                            },
                            onDrop: { model.addSidebarShortcuts($0) }
                        )
                    }
                    .frame(width: RailPeekLayout.hitWidth(isOpen: railPeekOpen), height: height, alignment: .leading)
                    .clipped()
                    .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: railPeekOpen)
                    .onChange(of: railDropTarget) { _, _ in updateRailVisibility() }
                    .zIndex(10)
                }
            }
        }
        .onChange(of: model.assistOpen) { _, _ in resetPeek() }
        .onChange(of: model.hideRail) { _, _ in resetPeek() }
        .onDisappear { closeTask?.cancel() }
    }

    private func updateRailVisibility() {
        closeTask?.cancel()
        if RailPeekLayout.shouldOpen(
            isRailHovering: railBodyHovering,
            isTriggerHovering: railTriggerHovering,
            isDropTarget: railDropTarget
        ) {
            railPeekOpen = true
        } else {
            // Crossing from the trigger into the moving rail emits a transient exit.
            closeTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                railPeekOpen = false
            }
        }
    }

    private func resetPeek() {
        closeTask?.cancel()
        railBodyHovering = false
        railTriggerHovering = false
        railDropTarget = false
        railPeekOpen = false
    }
}

struct ExplorerShellView: View {
    @EnvironmentObject private var model: ExplorerModel

    var body: some View {
        VStack(spacing: 0) {
            CommandSurfaceView()
            Divider()
            HSplitView {
                FilePaneView(pane: model.mainPane, role: .main)
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                if model.assistOpen {
                    VSplitView {
                        FilePaneView(pane: model.assistTopPane, role: .assist)
                            .frame(minHeight: 180, maxHeight: .infinity)
                        FilePaneView(pane: model.assistBottomPane, role: .assist)
                            .frame(minHeight: 180, maxHeight: .infinity)
                    }
                    .frame(minWidth: 340, idealWidth: 420, maxWidth: .infinity)
                }
            }
        }
    }
}
