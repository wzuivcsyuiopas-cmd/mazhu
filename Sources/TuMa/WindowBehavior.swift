// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct WindowBehavior: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowBehaviorView { WindowBehaviorView() }
    func updateNSView(_ view: WindowBehaviorView, context: Context) {
        if let window = view.window { WindowBehaviorView.configureChrome(in: window) }
    }
}

enum TitlebarDoubleClickAction: Equatable {
    case fill, zoom, minimize, none
    static func preference(_ value: String?) -> Self {
        switch value?.lowercased() {
        case "maximize", "fill": return .fill
        case "minimize", "miniaturize": return .minimize
        case "none": return .none
        default: return .zoom
        }
    }
}

final class WindowBehaviorView: NSView {
    private var monitor: Any?
    private var beforeFill: NSRect?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard let window else { return }
        Self.configureChrome(in: window)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }
    static func configureChrome(in window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window,
              !window.styleMask.contains(.fullScreen),
              event.locationInWindow.y >= window.contentLayoutRect.maxY,
              let frame = window.contentView?.superview,
              let hit = frame.hitTest(frame.convert(event.locationInWindow, from: nil)),
              !Self.isInsideToolbarItem(event.locationInWindow, in: window),
              !Self.isInteractiveTitlebarView(hit), hit.mouseDownCanMoveWindow else { return false }
        // SwiftUI toolbar spacers swallow these events. Hand the original event to
        // AppKit once; never calculate drag offsets or reposition during screen changes.
        if event.clickCount == 2 {
            let preference = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
            performDoubleClick(TitlebarDoubleClickAction.preference(preference), in: window)
        } else if event.clickCount == 1 {
            window.performDrag(with: event)
        }
        return true
    }

    static func isInsideToolbarItem(_ point: NSPoint, in window: NSWindow) -> Bool {
        for item in window.toolbar?.items ?? [] {
            guard item.itemIdentifier != .flexibleSpace, item.itemIdentifier != .space,
                  let view = item.view else { continue }
            if view.convert(view.bounds, to: nil).contains(point) { return true }
        }
        return false
    }

    static func isInteractiveTitlebarView(_ hit: NSView) -> Bool {
        var candidate: NSView? = hit
        while let view = candidate {
            // SwiftUI's native sidebar button hosts its glyph in a plain NSView.
            // Its toolbar-item ancestor exposes AXButton but is not an NSControl.
            if view is NSControl { return true }
            if let role = view.accessibilityRole(), [.button, .menuButton, .popUpButton, .checkBox, .radioButton, .tabGroup, .slider, .textField, .comboBox].contains(role) { return true }
            candidate = view.superview
        }
        return false
    }

    func performDoubleClick(_ action: TitlebarDoubleClickAction, in window: NSWindow) {
        switch action {
        case .none: break
        case .minimize: window.performMiniaturize(nil)
        case .zoom: window.performZoom(nil)
        case .fill:
            guard let screen = window.screen else { return }
            let target = screen.visibleFrame
            let current = window.frame
            let filled = abs(current.minX-target.minX)<1 && abs(current.minY-target.minY)<1 && abs(current.width-target.width)<1 && abs(current.height-target.height)<1
            if filled, var restore = beforeFill {
                restore.size.width = min(restore.width, target.width)
                restore.size.height = min(restore.height, target.height)
                window.setFrame(window.constrainFrameRect(restore, to: screen), display: true, animate: true)
                beforeFill = nil
            } else {
                beforeFill = current
                window.setFrame(target, display: true, animate: true)
            }
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
