import AppKit
import Combine
import SwiftUI

@main
@MainActor
struct XAlgoExplorerApp: App {
    @StateObject private var model = ExplorerModel()
    @StateObject private var commandContext = NativeCommandContext()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.thumbnails)
                .background(NativeCommandWindowBridge(commandContext: commandContext))
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            ExplorerCommands(model: model, commandContext: commandContext)
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 430)
        }
    }
}

@MainActor
struct ExplorerCommands: Commands {
    @ObservedObject var model: ExplorerModel
    @ObservedObject var commandContext: NativeCommandContext

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("\(model.commandText(.about)) \(AppMetadata.name)") {
                model.showAbout()
            }
            .help("\(model.commandText(.about)) \(AppMetadata.name)")
        }

        // PaneState publishes independently; observing only ExplorerModel misses selection changes.
        ExplorerPaneCommands(model: model, pane: model.focusedPane, commandContext: commandContext)
    }
}

@MainActor
private struct ExplorerPaneCommands: Commands {
    @ObservedObject var model: ExplorerModel
    @ObservedObject var pane: PaneState
    @ObservedObject var commandContext: NativeCommandContext

    private var fileCommandsEnabled: Bool {
        commandContext.canPerformFileCommands
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(model.commandText(.newFolder)) {
                performFileAction {
                    guard !model.isPerformingFileOperation else { return }
                    model.createFolder()
                }
            }
            .help(model.commandText(.newFolder))
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(!fileCommandsEnabled || !pane.isLocalDirectory || model.isPerformingFileOperation)

            Button(model.commandText(.newFile)) {
                performFileAction {
                    guard !model.isPerformingFileOperation else { return }
                    model.createFile()
                }
            }
            .help(model.commandText(.newFile))
            .keyboardShortcut("n", modifiers: [.control, .shift])
            .disabled(!fileCommandsEnabled || !pane.isLocalDirectory || model.isPerformingFileOperation)

            Divider()

            Button(model.commandText(.open)) {
                performFileAction { model.openSelection() }
            }
            .help(model.commandText(.open))
            .keyboardShortcut("o", modifiers: .command)
            .disabled(!fileCommandsEnabled || pane.selectedIDs.isEmpty)

            Button(model.commandText(.rename)) {
                performFileAction {
                    guard !model.isPerformingFileOperation else { return }
                    model.beginRenameSelection()
                }
            }
            .help(model.commandText(.rename))
            .disabled(!fileCommandsEnabled || !model.canRenameSelection || model.isPerformingFileOperation)

            Button(model.commandText(.moveToTrash)) {
                performFileAction {
                    guard !model.isPerformingFileOperation else { return }
                    model.trashSelection()
                }
            }
            .help(model.commandText(.moveToTrash))
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!fileCommandsEnabled || !pane.isLocalDirectory || pane.selectedIDs.isEmpty || model.isPerformingFileOperation)
        }

        CommandGroup(replacing: .pasteboard) {
            editingButton(.cut, title: .cut, key: "x")
            editingButton(.copy, title: .copy, key: "c")
            editingButton(.paste, title: .paste, key: "v")
        }

        CommandGroup(replacing: .textEditing) {
            editingButton(.selectAll, title: .selectAll, key: "a")
        }

        CommandGroup(after: .toolbar) {
            Menu(model.commandText(.viewMode)) {
                ForEach(ExplorerViewMode.allCases) { mode in
                    Toggle(isOn: Binding(
                        get: { pane.viewMode == mode },
                        set: { selected in
                            guard selected, model.availableViewModesForFocusedPane.contains(mode) else { return }
                            performFileAction { model.setViewMode(mode) }
                        }
                    )) {
                        Label(NativeCommandText.viewMode(mode, language: model.language), systemImage: mode.symbolName)
                    }
                    .help(NativeCommandText.viewMode(mode, language: model.language))
                    .keyboardShortcut(shortcut(for: mode), modifiers: .command)
                    .disabled(!model.availableViewModesForFocusedPane.contains(mode))
                }
            }
            .help(model.commandText(.viewMode))
            .disabled(!fileCommandsEnabled)

            Picker(model.commandText(.sortBy), selection: Binding(
                get: { pane.sortField },
                set: { field in performFileAction { model.setSortField(field) } }
            )) {
                ForEach(SortField.allCases) { field in
                    Text(NativeCommandText.sortField(field, language: model.language)).tag(field)
                }
            }
            .help(model.commandText(.sortBy))
            .disabled(!fileCommandsEnabled)

            Button(model.commandText(pane.sortAscending ? .descending : .ascending)) {
                performFileAction { model.toggleSortDirection() }
            }
            .help(model.commandText(pane.sortAscending ? .descending : .ascending))
            .disabled(!fileCommandsEnabled)

            Divider()

            Button(model.commandText(.search)) {
                guard commandContext.activeWorkspaceWindow != nil else { return }
                model.openSearch()
            }
            .help(model.commandText(.search))
            .keyboardShortcut("f", modifiers: .command)
            .disabled(commandContext.activeWorkspaceWindow == nil)

            Button(model.commandText(.refresh)) {
                performFileAction { model.refreshFocusedPane() }
            }
            .help(model.commandText(.refresh))
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!fileCommandsEnabled)
        }

        CommandMenu(model.commandText(.goMenu)) {
            Button(model.commandText(.goBack)) {
                performFileAction { model.goBack() }
            }
            .help(model.commandText(.goBack))
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!fileCommandsEnabled || !pane.canGoBack)

            Button(model.commandText(.goForward)) {
                performFileAction { model.goForward() }
            }
            .help(model.commandText(.goForward))
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!fileCommandsEnabled || !pane.canGoForward)

            Button(model.commandText(.goUp)) {
                performFileAction { model.goUp() }
            }
            .help(model.commandText(.goUp))
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(!fileCommandsEnabled || !pane.canGoUp)

            Divider()

            Button(model.commandText(.nextPane)) {
                movePaneFocus(backwards: false)
            }
            .help(model.commandText(.nextPane))
            .keyboardShortcut("]", modifiers: [.command, .option])
            .disabled(commandContext.activeWorkspaceWindow == nil || !model.assistOpen)

            Button(model.commandText(.previousPane)) {
                movePaneFocus(backwards: true)
            }
            .help(model.commandText(.previousPane))
            .keyboardShortcut("[", modifiers: [.command, .option])
            .disabled(commandContext.activeWorkspaceWindow == nil || !model.assistOpen)
        }
    }

    private func editingButton(_ action: NativeEditingAction, title: NativeCommandKey, key: KeyEquivalent) -> some View {
        Button(model.commandText(title)) {
            NativeCommandRouting.perform(action, model: model, context: commandContext)
        }
        .help(model.commandText(title))
        .keyboardShortcut(key, modifiers: .command)
        .disabled(!NativeCommandRouting.canPerform(action, model: model, context: commandContext))
    }

    private func performFileAction(_ action: () -> Void) {
        guard fileCommandsEnabled else { return }
        action()
    }

    private func shortcut(for mode: ExplorerViewMode) -> KeyEquivalent {
        switch mode {
        case .list: "1"
        case .files: "2"
        case .preview: "3"
        }
    }

    private func movePaneFocus(backwards: Bool) {
        guard let window = commandContext.activeWorkspaceWindow, model.assistOpen else { return }
        NativeCommandRouting.movePaneFocus(model: model, in: window, backwards: backwards)
    }
}

enum NativeEditingAction: CaseIterable {
    case cut, copy, paste, selectAll

    var selector: Selector {
        switch self {
        case .cut: #selector(NSText.cut(_:))
        case .copy: #selector(NSText.copy(_:))
        case .paste: #selector(NSText.paste(_:))
        case .selectAll: #selector(NSText.selectAll(_:))
        }
    }
}

@MainActor
enum NativeCommandRouting {
    static func isTextInput(_ responder: NSResponder?) -> Bool {
        responder is NSText || responder is NSTextField || responder is NSTextInputClient
    }

    static func canPerform(_ action: NativeEditingAction, model: ExplorerModel, context: NativeCommandContext) -> Bool {
        if isTextInput(NSApp.keyWindow?.firstResponder) || context.activeWorkspaceWindow == nil {
            return canSendToResponder(action)
        }
        return canPerformFileEditing(action, model: model)
    }

    static func canPerformFileEditing(_ action: NativeEditingAction, model: ExplorerModel) -> Bool {
        switch action {
        case .cut: return model.focusedPane.isLocalDirectory && model.hasSelection
        case .copy: return model.hasSelection
        case .paste: return model.canPaste
        case .selectAll: return !model.displayedEntries(for: model.focusedPane).isEmpty
        }
    }

    @discardableResult
    static func perform(_ action: NativeEditingAction, model: ExplorerModel, context: NativeCommandContext) -> Bool {
        routeEditing(
            action,
            firstResponder: NSApp.keyWindow?.firstResponder,
            isWorkspace: context.activeWorkspaceWindow != nil,
            sendToResponder: { selector in
                guard canSendToResponder(action) else { return false }
                return NSApp.sendAction(selector, to: nil, from: nil)
            },
            fileAction: {
                guard canPerform(action, model: model, context: context) else { return false }
                switch action {
                case .cut: model.cutSelection()
                case .copy: model.copySelection()
                case .paste: model.pasteClipboard()
                case .selectAll: model.selectAllFocused()
                }
                return true
            }
        )
    }

    static func routeEditing(
        _ action: NativeEditingAction,
        firstResponder: NSResponder?,
        isWorkspace: Bool,
        sendToResponder: (Selector) -> Bool,
        fileAction: () -> Bool
    ) -> Bool {
        // An unhandled text command must never fall back to an operation on selected files.
        if isTextInput(firstResponder) || !isWorkspace {
            return sendToResponder(action.selector)
        }
        return fileAction()
    }

    static func nextPane(after pane: PaneID, backwards: Bool) -> PaneID {
        let panes: [PaneID] = [.main, .assistTop, .assistBottom]
        let index = panes.firstIndex(of: pane) ?? 0
        return panes[(index + (backwards ? panes.count - 1 : 1)) % panes.count]
    }

    static func focusedPane(in window: NSWindow) -> PaneID? {
        var view = window.firstResponder as? NSView
        while let current = view {
            if let pane = PaneID.allCases.first(where: { current.identifier == NativePaneFocus.identifier(for: $0) }) {
                return pane
            }
            view = current.superview
        }
        return nil
    }

    @discardableResult
    static func movePaneFocus(model: ExplorerModel, in window: NSWindow, backwards: Bool) -> Bool {
        guard model.assistOpen, window.attachedSheet == nil else { return false }
        let current = focusedPane(in: window) ?? model.focusedPaneID
        let target = nextPane(after: current, backwards: backwards)
        NativePaneFocus.request(target, in: window)
        // Do not change logical focus if an editor refused to resign or the target is absent.
        guard focusedPane(in: window) == target else { return false }
        model.setFocus(target)
        return true
    }

    private static func canSendToResponder(_ action: NativeEditingAction) -> Bool {
        guard let target = NSApp.target(forAction: action.selector, to: nil, from: nil) else { return false }
        let item = NSMenuItem(title: "", action: action.selector, keyEquivalent: "")
        if let validator = target as? NSMenuItemValidation {
            return validator.validateMenuItem(item)
        }
        if let validator = target as? NSUserInterfaceValidations {
            return validator.validateUserInterfaceItem(item)
        }
        return true
    }
}

@MainActor
final class NativeCommandContext: ObservableObject {
    @Published private(set) var revision = 0
    private let workspaceWindows = NSHashTable<NSWindow>.weakObjects()
    private var subscriptions: Set<AnyCancellable> = []

    init() {
        let notifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification, NSMenu.didBeginTrackingNotification,
            NSControl.textDidBeginEditingNotification, NSControl.textDidEndEditingNotification,
            NSText.didBeginEditingNotification, NSText.didEndEditingNotification,
            NSText.didChangeNotification, NSTextView.didChangeSelectionNotification
        ]
        for name in notifications {
            NotificationCenter.default.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.revision &+= 1 }
                .store(in: &subscriptions)
        }
    }

    var activeWorkspaceWindow: NSWindow? {
        guard let window = NSApp.keyWindow,
              workspaceWindows.contains(window),
              window.attachedSheet == nil,
              NSApp.modalWindow == nil else { return nil }
        return window
    }

    var canPerformFileCommands: Bool {
        guard let window = activeWorkspaceWindow else { return false }
        return !NativeCommandRouting.isTextInput(window.firstResponder)
    }

    func register(_ window: NSWindow) {
        guard !workspaceWindows.contains(window) else { return }
        workspaceWindows.add(window)
        invalidate()
    }

    func unregister(_ window: NSWindow) {
        workspaceWindows.remove(window)
        invalidate()
    }

    private func invalidate() {
        // NSView attachment can happen inside a SwiftUI update.
        DispatchQueue.main.async { [weak self] in self?.revision &+= 1 }
    }
}

private struct NativeCommandWindowBridge: NSViewRepresentable {
    let commandContext: NativeCommandContext

    func makeNSView(context: Context) -> NativeCommandWindowView {
        NativeCommandWindowView(commandContext: commandContext)
    }

    func updateNSView(_ nsView: NativeCommandWindowView, context: Context) {}

    static func dismantleNSView(_ nsView: NativeCommandWindowView, coordinator: ()) {
        if let window = nsView.window {
            nsView.commandContext.unregister(window)
        }
    }
}

private final class NativeCommandWindowView: NSView {
    let commandContext: NativeCommandContext

    init(commandContext: NativeCommandContext) {
        self.commandContext = commandContext
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window, window !== newWindow {
            commandContext.unregister(window)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        commandContext.register(window)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
