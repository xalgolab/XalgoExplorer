import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CollapsedRailStripView: View {
    let height: CGFloat

    var body: some View {
        Capsule()
            .fill(.clear)
            .frame(width: RailPeekLayout.collapsedHitWidth)
            .frame(height: height)
            .capsuleSurface()
            .clipShape(Capsule())
    }
}

enum RailPeekLayout {
    static let collapsedHitWidth: CGFloat = 14
    static let expandedHitWidth: CGFloat = 62
    static let railBodyWidth: CGFloat = expandedHitWidth
    static let railIconColumnWidth: CGFloat = 44
    static let railLeadingPadding: CGFloat = 10
    static let railTrailingPadding: CGFloat = railBodyWidth - railIconColumnWidth - railLeadingPadding
    static let dockedRailSlotWidth: CGFloat = railBodyWidth
    static let railButtonSize: CGFloat = 30
    static let railStackSpacing: CGFloat = 4
    static let railVerticalPadding: CGFloat = 8
    static let userShortcutDividerLineHeight: CGFloat = 1
    static let userShortcutDividerVerticalPadding: CGFloat = 4
    static let utilityGapHeight: CGFloat = 68
    static let clipsRailBody = true

    static var userShortcutDividerHeight: CGFloat {
        userShortcutDividerLineHeight + userShortcutDividerVerticalPadding * 2
    }

    static func hitWidth(isOpen: Bool) -> CGFloat {
        isOpen ? expandedHitWidth : collapsedHitWidth
    }

    static func railOffset(isOpen: Bool) -> CGFloat {
        isOpen ? 0 : -expandedHitWidth
    }

    static func shouldOpen(isHovering: Bool, isDropTarget: Bool) -> Bool {
        shouldOpen(isRailHovering: isHovering, isTriggerHovering: false, isDropTarget: isDropTarget)
    }

    static func shouldOpen(isRailHovering: Bool, isTriggerHovering: Bool, isDropTarget: Bool) -> Bool {
        isRailHovering || isTriggerHovering || isDropTarget
    }

    static func triggerWidth(isDropTarget: Bool) -> CGFloat {
        isDropTarget ? expandedHitWidth : collapsedHitWidth
    }

    static func railContentHeight(defaultCount: Int, userCount: Int, utilityCount: Int) -> CGFloat {
        let buttonCount = defaultCount + userCount + utilityCount
        let dividerCount = userCount > 0 ? 1 : 0
        let utilityGapCount = 1
        let childCount = buttonCount + dividerCount + utilityGapCount
        let spacingHeight = CGFloat(max(childCount - 1, 0)) * railStackSpacing
        let dividerHeight = userCount > 0 ? userShortcutDividerHeight : 0

        return CGFloat(buttonCount) * railButtonSize
            + dividerHeight
            + utilityGapHeight
            + spacingHeight
            + railVerticalPadding * 2
    }

    static func collapsedStripHeight(defaultCount: Int, userCount: Int, utilityCount: Int) -> CGFloat {
        railContentHeight(defaultCount: defaultCount, userCount: userCount, utilityCount: utilityCount)
    }
}

enum RailShortcutDropTypes {
    static let accepted: [UTType] = [.fileURL, .xAlgoInternalFileDrag]
    static let pasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        NSPasteboard.PasteboardType(UTType.fileURL.identifier),
        NSPasteboard.PasteboardType(UTType.xAlgoInternalFileDrag.identifier)
    ]
}

struct RailPeekTriggerView: View {
    let width: CGFloat
    let height: CGFloat
    @Binding var isDropTarget: Bool
    let onHover: (Bool) -> Void
    let onDrop: ([URL]) -> Bool

    var body: some View {
        RailPeekEventBridge(
            isDropTarget: $isDropTarget,
            onHover: onHover,
            onDrop: onDrop
        )
        .frame(width: width)
        .frame(height: height)
        .contentShape(Rectangle())
    }
}

struct RailPeekEventBridge: NSViewRepresentable {
    @Binding var isDropTarget: Bool
    let onHover: (Bool) -> Void
    let onDrop: ([URL]) -> Bool

    func makeNSView(context: Context) -> RailPeekEventView {
        let view = RailPeekEventView()
        view.registerForDraggedTypes(RailShortcutDropTypes.pasteboardTypes)
        return view
    }

    func updateNSView(_ nsView: RailPeekEventView, context: Context) {
        nsView.onHover = onHover
        nsView.onDrop = onDrop
        nsView.onDropTargetChange = { targeted in
            if isDropTarget != targeted {
                isDropTarget = targeted
            }
        }
    }
}

final class RailPeekEventView: NSView {
    var onHover: ((Bool) -> Void)?
    var onDropTargetChange: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Bool)?

    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let next = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        trackingAreaRef = next
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseDown(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDropTargetChange?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDropTargetChange?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDropTargetChange?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDropTargetChange?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = RailShortcutPasteboardReader.urls(from: sender.draggingPasteboard)
        let didDrop = onDrop?(urls) ?? false
        onDropTargetChange?(false)
        return didDrop
    }
}

enum RailShortcutPasteboardReader {
    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []

        if let nsURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] {
            urls.append(contentsOf: nsURLs.compactMap { $0 as URL })
        }

        if let fileURLString = pasteboard.string(forType: .fileURL),
           let url = URL(string: fileURLString),
           url.isFileURL {
            urls.append(url)
        }

        let internalType = NSPasteboard.PasteboardType(UTType.xAlgoInternalFileDrag.identifier)
        if let data = pasteboard.data(forType: internalType) {
            urls.append(contentsOf: Self.urls(fromInternalDragData: data))
        }

        return uniqueFileURLs(urls)
    }

    static func urls(fromInternalDragData data: Data) -> [URL] {
        guard let payload = try? JSONDecoder().decode(InternalFileDragPayload.self, from: data) else {
            return []
        }
        return payload.paths.map { URL(fileURLWithPath: $0) }
    }

    private static func uniqueFileURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var unique: [URL] = []
        for url in urls where url.isFileURL {
            let standardized = url.standardizedFileURL
            if seen.insert(standardized.path).inserted {
                unique.append(standardized)
            }
        }
        return unique
    }
}

struct RailView: View {
    @EnvironmentObject private var model: ExplorerModel
    let maxHeight: CGFloat
    @State private var isDropTarget = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: RailPeekLayout.railStackSpacing) {
                ForEach(model.defaultSidebarTargets) { RailButton(target: $0) }
                if !model.userSidebarTargets.isEmpty {
                    Divider()
                        .frame(width: 22)
                        .padding(.vertical, RailPeekLayout.userShortcutDividerVerticalPadding)
                    ForEach(model.userSidebarTargets) { RailButton(target: $0) }
                }
                Color.clear.frame(height: RailPeekLayout.utilityGapHeight)
                ForEach(model.utilitySidebarTargets) { RailButton(target: $0) }
            }
            .frame(width: RailPeekLayout.railIconColumnWidth)
            .padding(.vertical, RailPeekLayout.railVerticalPadding)
            .padding(.leading, RailPeekLayout.railLeadingPadding)
            .padding(.trailing, RailPeekLayout.railTrailingPadding)
        }
        .scrollIndicators(.hidden)
        .frame(width: RailPeekLayout.railBodyWidth, height: maxHeight)
        .capsuleSurface(isHighlighted: isDropTarget)
        .contentShape(Capsule())
        .onDrop(of: RailShortcutDropTypes.accepted, isTargeted: $isDropTarget) {
            model.handleSidebarShortcutDrop($0)
        }
        .contextMenu { DefaultSidebarVisibilityMenu() }
    }
}

struct RailButton: View {
    @EnvironmentObject private var model: ExplorerModel
    let target: SidebarTarget
    @State private var isDropTarget = false

    var body: some View {
        NativeSymbolButton(title: target.title, symbol: target.symbolName) {
            model.openSidebarTarget(target)
            NativePaneFocus.request(.main)
        }
        .frame(width: RailPeekLayout.railButtonSize, height: RailPeekLayout.railButtonSize)
        .onDrop(of: RailShortcutDropTypes.accepted, isTargeted: $isDropTarget) { providers in
            model.handleSidebarShortcutDrop(providers)
        }
        .contextMenu {
            switch target.group {
            case .appDefault:
                DefaultSidebarVisibilityMenu()
            case .userShortcut:
                Button(model.commandText(.removeShortcut)) {
                    model.removeSidebarShortcut(target)
                }
            case .mountedVolume:
                Button(model.commandText(.eject)) {
                    model.ejectVolume(target)
                }
            case .utility:
                EmptyView()
            }
        }
    }
}

struct DefaultSidebarVisibilityMenu: View {
    @EnvironmentObject private var model: ExplorerModel

    var body: some View {
        Section(model.commandText(.fixedIcons)) {
            ForEach(model.allDefaultSidebarTargets) { target in
                Toggle(isOn: Binding(
                    get: { model.isDefaultSidebarTargetVisible(target) },
                    set: { model.setDefaultSidebarTarget(target, visible: $0) }
                )) {
                    Label(target.title, systemImage: target.symbolName)
                }
            }
        }
    }
}
