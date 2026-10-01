import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WindowConfigurator: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughNSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(view.window)
            context.coordinator.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
        if context.coordinator.window !== nsView.window {
            DispatchQueue.main.async {
                configureWindow(nsView.window)
                context.coordinator.window = nsView.window
            }
        }
    }

    private func configureWindow(_ window: NSWindow?) {
        guard let window else { return }
        window.title = "xAlgo Explorer"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask.remove(.fullSizeContentView)
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.minSize = NSSize(width: 960, height: 640)
    }

    final class Coordinator {
        weak var window: NSWindow?
        var onKeyDown: (NSEvent) -> Bool
        private var monitor: Any?

        init(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
            self.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard event.window == self.window else { return event }
                return self.onKeyDown(event) ? nil : event
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    final class PassthroughNSView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

extension Color {
    static var controlBorder: Color {
        Color(nsColor: .separatorColor).opacity(0.42)
    }

    static var rowHover: Color {
        Color(nsColor: .labelColor).opacity(0.09)
    }

    static var selectedCapsule: Color {
        Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
    }

    static var previewLabelBackground: Color {
        Color(nsColor: .textBackgroundColor).opacity(0.82)
    }
}
