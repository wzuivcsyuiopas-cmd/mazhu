// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// Stable slots and a fixed AppKit host prevent symbol fitting from moving the toolbar.
struct ToolPicker: NSViewRepresentable {
    static let slotWidth: CGFloat = 48
    static let controlHeight: CGFloat = 32
    static let height: CGFloat = 36
    static var controlWidth: CGFloat { CGFloat(MarkTool.allCases.count) * slotWidth + 24 }
    static var width: CGFloat { controlWidth + 12 }
    @Binding var selection: MarkTool
    var isEnabled: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> ToolPickerHost {
        let host = ToolPickerHost()
        host.control.target = context.coordinator
        host.control.action = #selector(Coordinator.changed(_:))
        return host
    }
    func updateNSView(_ host: ToolPickerHost, context: Context) {
        context.coordinator.parent = self
        let index = MarkTool.allCases.firstIndex(of: selection) ?? 0
        if host.control.selectedSegment != index { host.control.selectedSegment = index }
        if host.control.isEnabled != isEnabled { host.control.isEnabled = isEnabled }
    }
    final class Coordinator: NSObject {
        var parent: ToolPicker
        init(_ parent: ToolPicker) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) {
            guard MarkTool.allCases.indices.contains(sender.selectedSegment) else { return }
            parent.selection = MarkTool.allCases[sender.selectedSegment]
        }
    }
}
final class ToolPickerHost: NSGlassEffectView {
    private let content = NSView()
    let control = NSSegmentedControl()
    override var intrinsicContentSize: NSSize { NSSize(width: ToolPicker.width, height: ToolPicker.height) }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        style = .regular
        cornerRadius = ToolPicker.height / 2
        clipsToBounds = false
        content.clipsToBounds = false
        // Public macOS 27 API; the installed compiler uses SDK 26.2.
        let interactiveSetter = NSSelectorFromString("setEffectIsInteractive:")
        if #available(macOS 27.0, *), responds(to: interactiveSetter) {
            typealias SetInteractive = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(method(for: interactiveSetter), to: SetInteractive.self)(self, interactiveSetter, true)
        }
        contentView = content
        control.segmentCount = MarkTool.allCases.count
        control.trackingMode = .selectOne
        control.segmentStyle = .automatic
        control.borderShape = .capsule
        control.segmentDistribution = .fit
        control.controlSize = .large
        control.setAccessibilityLabel("打码工具")
        for (index, tool) in MarkTool.allCases.enumerated() {
            let symbol = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.title)?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
            let icon = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { bounds in
                guard let symbol else { return false }
                let factor = min(bounds.width/symbol.size.width, bounds.height/symbol.size.height)
                let size = NSSize(width:symbol.size.width*factor,height:symbol.size.height*factor)
                symbol.draw(in:NSRect(x:bounds.midX-size.width/2,y:bounds.midY-size.height/2,width:size.width,height:size.height))
                return true
            }
            icon.isTemplate = true
            icon.accessibilityDescription = tool.title
            control.setImage(icon, forSegment: index)
            control.setToolTip(tool.title, forSegment: index)
            control.setWidth(ToolPicker.slotWidth, forSegment: index)
            control.setImageScaling(.scaleNone, forSegment: index)
        }
        // Public macOS 27 API, bridged for the installed SDK 26.2 compiler.
        let setter = NSSelectorFromString("setRole:")
        if #available(macOS 27.0, *), control.responds(to: setter) {
            typealias SetRole = @convention(c) (AnyObject, Selector, Int) -> Void
            unsafeBitCast(control.method(for: setter), to: SetRole.self)(control, setter, 1)
        }
        content.addSubview(control)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let frame = NSRect(x:6,y:(bounds.height-ToolPicker.controlHeight)/2,width:ToolPicker.controlWidth,height:ToolPicker.controlHeight)
        if control.frame != frame { control.frame = frame }
    }
}
