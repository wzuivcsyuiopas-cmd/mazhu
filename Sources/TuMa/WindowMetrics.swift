// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// Passive diagnostics for isolated UI checks; never observes or writes in a normal session.
struct WindowMetrics: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowMetricsView { WindowMetricsView() }
    func updateNSView(_ view: WindowMetricsView, context: Context) {}
}
final class WindowMetricsView: NSView {
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        guard ProcessInfo.processInfo.environment["TUMA_TEST_WORKSPACE"] != nil, let window else { return }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main) { [weak self] note in
                MainActor.assumeIsolated { self?.record(note.name.rawValue) }
            })
        }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching:.leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { if event.window === self?.window { self?.record("mouse-down \(event.clickCount) \(event.locationInWindow)", at: event.locationInWindow) } }
            return event
        }
        DispatchQueue.main.async { [weak self] in self?.record("attached") }
    }
    private func record(_ event: String, at eventPoint: NSPoint? = nil) {
        guard let window, let root = ProcessInfo.processInfo.environment["TUMA_TEST_WORKSPACE"] else { return }
        let frameView = window.contentView?.superview
        let point = frameView?.convert(eventPoint ?? NSPoint(x:560,y:window.frame.height-24),from:nil) ?? .zero
        let hit = frameView?.hitTest(point)
        var ancestry: [String] = []
        var ancestor = hit
        while let view = ancestor {
            ancestry.append("\(type(of:view)) role=\(view.accessibilityRole()?.rawValue ?? "nil") control=\(view is NSControl)")
            ancestor = view.superview
        }
        var glass: [[String: Any]] = []
        func collectGlass(_ view: NSView) {
            if let effect = view as? NSGlassEffectView, effect.responds(to: NSSelectorFromString("effectIsInteractive")) {
                glass.append(["frame": NSStringFromRect(effect.convert(effect.bounds, to: nil)), "interactive": effect.value(forKey: "effectIsInteractive") ?? false])
            }
            for child in view.subviews { collectGlass(child) }
        }
        if let frameView { collectGlass(frameView) }
        let items = (window.toolbar?.items ?? []).map { item -> [String: Any] in
            ["id": item.itemIdentifier.rawValue, "frame": item.view.map { NSStringFromRect($0.convert($0.bounds, to: nil)) } ?? "nil"]
        }
        let data: [String:Any] = ["items":items,"insideToolbarItem":eventPoint.map { WindowBehaviorView.isInsideToolbarItem($0, in: window) } ?? false,"glass":glass,"hitAncestry":ancestry,"titleHit":hit.map { String(describing:type(of:$0)) } ?? "none","titleCanDrag":hit?.mouseDownCanMoveWindow ?? false,"event":event,"frame":NSStringFromRect(window.frame),"min":NSStringFromSize(window.minSize),"contentMin":NSStringFromSize(window.contentMinSize),"max":NSStringFromSize(window.maxSize),"screen":window.screen?.localizedName ?? "none","screenFrame":NSStringFromRect(window.screen?.frame ?? .zero),"visibleFrame":NSStringFromRect(window.screen?.visibleFrame ?? .zero),"contentLayout":NSStringFromRect(window.contentLayoutRect),"zoomed":window.isZoomed,"movable":window.isMovable,"backgroundDrag":window.isMovableByWindowBackground]
        guard let bytes = try? JSONSerialization.data(withJSONObject:data,options:[.sortedKeys]), let line = String(data:bytes,encoding:.utf8) else { return }
        let url = URL(fileURLWithPath:root).appendingPathComponent("window-metrics.jsonl")
        let old = (try? String(contentsOf:url,encoding:.utf8)) ?? ""
        try? (old+line+"\n").write(to:url,atomically:true,encoding:.utf8)
    }
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    }
}
