import AppKit
import SwiftUI

struct NativeGlassContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func capsuleSurface(isHighlighted: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(
                .regular.tint(isHighlighted ? .accentColor.opacity(0.18) : nil),
                in: Capsule()
            )
        } else {
            background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.controlBorder, lineWidth: 0.5))
                .overlay {
                    if isHighlighted {
                        Capsule().fill(Color.accentColor.opacity(0.12))
                    }
                }
        }
    }
}

// AppKit owns tracking, tooltips, accessibility, and the pressed state.
struct NativeSymbolButton: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let symbol: String
    var isSelected = false
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.showsBorderOnlyWhileMouseInside = true
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.controlSize = .regular
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.symbolConfiguration = .init(pointSize: 16, weight: .regular)
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.title = ""
        button.imagePosition = .imageOnly
        button.isEnabled = isEnabled
        button.contentTintColor = isSelected ? .controlAccentColor : .labelColor
        button.state = isSelected ? .on : .off
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: (() -> Void)?
        @objc func performAction() { action?() }
    }
}

enum NativePaneFocus {
    static func identifier(for id: PaneID) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("file-area-\(id.rawValue)")
    }

    @MainActor
    static func request(_ paneID: PaneID, in window: NSWindow? = NSApp.keyWindow) {
        guard let window, let root = window.contentView,
              let target = find(identifier(for: paneID), in: root) else { return }
        window.makeFirstResponder(target)
    }

    @MainActor
    static func requestSearch(in window: NSWindow? = NSApp.keyWindow) {
        guard let window, let root = window.contentView,
              let target = find(NSUserInterfaceItemIdentifier("workspace-search"), in: root) else { return }
        window.makeFirstResponder(target)
    }

    @MainActor
    static func isFileArea(_ responder: NSResponder?) -> Bool {
        guard let view = responder as? NSView else { return false }
        return PaneID.allCases.contains { view.identifier == identifier(for: $0) }
    }

    @MainActor
    private static func find(_ identifier: NSUserInterfaceItemIdentifier, in view: NSView) -> NSView? {
        if view.identifier == identifier { return view }
        for child in view.subviews {
            if let result = find(identifier, in: child) { return result }
        }
        return nil
    }
}

struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onClose: () -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = WorkspaceSearchField()
        field.controlSize = .regular
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchAction(_:))
        field.identifier = NSUserInterfaceItemIdentifier("workspace-search")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        init(_ parent: NativeSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        @objc func searchAction(_ sender: NSSearchField) {
            parent.text = sender.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onClose()
                return true
            }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

@MainActor
private final class WorkspaceSearchField: NSSearchField {
    private var didRequestFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !didRequestFocus else { return }
        didRequestFocus = window.makeFirstResponder(self)
    }
}
