// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct NativeCanvas: NSViewRepresentable {
    @ObservedObject var model: WorkspaceModel
    func makeNSView(context: Context) -> CanvasScrollView {
        let scroll = CanvasScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scroll.borderType = .noBorder
        scroll.canvas.model = model
        scroll.documentView = scroll.canvas
        return scroll
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CanvasScrollView, context: Context) -> CGSize? {
        // The document may be much larger than the viewport. It must never drive window sizing.
        CGSize(width: max(0, proposal.width ?? 800), height: max(0, proposal.height ?? 600))
    }
    func updateNSView(_ scroll: CanvasScrollView, context: Context) {
        scroll.canvas.model = model
        scroll.canvas.sync()
        scroll.layoutCanvas()
    }
}
final class CanvasScrollView: NSScrollView {
    let canvas = DrawingCanvas(frame: .zero)
    override var mouseDownCanMoveWindow: Bool { false }
    override class var isCompatibleWithResponsiveScrolling: Bool { true }
    override func scrollWheel(with event: NSEvent) {
        if !canvas.handleScrollWheel(event) { super.scrollWheel(with: event) }
    }
    override func layout() { super.layout(); layoutCanvas() }
    func layoutCanvas() { canvas.arrange(in: contentSize) }
}
final class DrawingCanvas: NSView {
    weak var model: WorkspaceModel?
    private var renderer: ImageRenderer?
    private var displayed: NSImage?
    private var photoID: UUID?
    private var imageIdentity: ObjectIdentifier?
    private var seenRevision = -1
    private var activeStroke: MarkStroke?
    private var strokeBase: CGImage?
    private let glassCursor = GlassCursorView(frame: .zero)
    private var imageRect = CGRect.zero
    private var scale = 1.0
    private var cursorPoint: CGPoint? { didSet { updateGlassCursor() } }
    private var tracking: NSTrackingArea?
    private var viewport = CGSize.zero
    private var wheelRemainder = 0.0
    private var wheelSetting = ""
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glassCursor.style = .clear
        glassCursor.isHidden = true
        glassCursor.contentView = NSView(frame: .zero)
        glassCursor.setAccessibilityElement(false)
        addSubview(glassCursor)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow,.inVisibleRect,.mouseMoved,.mouseEnteredAndExited], owner: self)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }
    func sync() {
        guard let model else { return }
        model.finishDrawing = { [weak self] in self?.finishStroke() }
        model.controlHoverChanged = { [weak self] in
            guard let self else { return }
            self.updateGlassCursor()
            self.window?.invalidateCursorRects(for: self)
        }
        guard let original = model.image, let photo = model.selected else {
            renderer = nil; displayed = nil; photoID = nil; imageIdentity = nil; glassCursor.isHidden = true; needsDisplay = true; return
        }
        let identity = ObjectIdentifier(original)
        do {
            if photoID != photo.id || imageIdentity != identity {
                renderer = try ImageRenderer(original: original)
                photoID = photo.id; imageIdentity = identity; activeStroke = nil; strokeBase = nil; seenRevision = -1
            }
            if seenRevision != model.revision {
                if let rendered = try renderer?.render(photo.strokes) {
                    displayed = NSImage(cgImage: rendered, size: CGSize(width: original.width, height: original.height))
                    // Update thumbnails following undo/redo as well as normal painting.
                    let thumb = ImageCodec.thumbnail(rendered)
                    DispatchQueue.main.async { [weak model] in
                        if model?.selected?.id == photo.id { model?.thumbnails[photo.id] = thumb }
                    }
                }
                seenRevision = model.revision
            }
        } catch { model.errorMessage = error.localizedDescription }
        updateGlassCursor()
        needsDisplay = true
    }
    func arrange(in size: CGSize) {
        viewport = size
        guard let model, let image = model.image else { setFrameSize(size); return }
        let top = 80.0, bottom = size.width < 800 ? 210.0 : 140.0
        let fit = min(max(1,size.width-72)/Double(image.width),max(1,size.height-top-bottom)/Double(image.height),1)
        scale = model.zoom == 0 ? fit : model.zoom
        scale = max(0.01,scale)
        let w = Double(image.width)*scale, h = Double(image.height)*scale
        let frameSize = CGSize(width: max(size.width,w+72),height:max(size.height,h+top+bottom))
        if frame.size != frameSize { setFrameSize(frameSize) }
        imageRect = CGRect(x:(frameSize.width-w)/2,y:top+(frameSize.height-top-bottom-h)/2,width:w,height:h)
        updateGlassCursor()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let displayed else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:imageRect).addClip()
        NSColor.white.setFill(); imageRect.fill()
        let square = 12.0
        NSColor(white:0.92,alpha:1).setFill()
        let clip = imageRect.intersection(dirtyRect)
        if !clip.isEmpty {
            let left = max(0,Int((clip.minX-imageRect.minX)/square))
            let top = max(0,Int((clip.minY-imageRect.minY)/square))
            let right = Int(ceil((clip.maxX-imageRect.minX)/square)), bottom = Int(ceil((clip.maxY-imageRect.minY)/square))
            for y in top..<bottom { for x in left..<right where (x+y)%2 == 0 {
                NSRect(x:imageRect.minX+Double(x)*square,y:imageRect.minY+Double(y)*square,width:square,height:square).fill()
            } }
        }
        displayed.draw(in:imageRect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high.rawValue])
        NSGraphicsContext.restoreGraphicsState()
        if let stroke = activeStroke, stroke.tool == .lasso, let first = stroke.points.first {
            let outline = NSBezierPath()
            func screen(_ p: MarkPoint) -> CGPoint { CGPoint(x:imageRect.minX+p.x*scale,y:imageRect.minY+p.y*scale) }
            outline.move(to:screen(first))
            for p in stroke.points.dropFirst() { outline.line(to:screen(p)) }
            outline.close()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect:imageRect).addClip()
            outline.windingRule = .evenOdd
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill(); outline.fill()
            outline.lineWidth = 1.5; outline.setLineDash([5,4], count:2, phase:0)
            NSColor.controlAccentColor.setStroke(); outline.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    private func updateGlassCursor() {
        guard let p = cursorPoint, imageRect.contains(p), let model, model.image != nil, !model.busy, !model.pointerOverControls else {
            glassCursor.isHidden = true; return
        }
        let diameter = model.tool == .lasso || model.tool == .line ? 18.0 : max(12, model.brushSize)
        glassCursor.frame = CGRect(x:p.x-diameter/2,y:p.y-diameter/2,width:diameter,height:diameter)
        glassCursor.cornerRadius = diameter/2
        glassCursor.isHidden = false
    }
    private static let invisibleCursor: NSCursor = {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus(); NSColor.clear.setFill(); NSRect(x:0,y:0,width:1,height:1).fill(using:.copy); image.unlockFocus()
        return NSCursor(image:image,hotSpot:.zero)
    }()
    override func resetCursorRects() {
        if model?.image != nil && model?.busy == false && model?.pointerOverControls == false { addCursorRect(imageRect,cursor:Self.invisibleCursor) }
    }
    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow,from:nil) }
    private func imagePoint(_ p: CGPoint) -> MarkPoint { MarkPoint(CGPoint(x:(p.x-imageRect.minX)/scale,y:(p.y-imageRect.minY)/scale)) }
    override func mouseMoved(with event: NSEvent) { cursorPoint = point(event) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with:event) }
    override func mouseExited(with event: NSEvent) { cursorPoint = nil }
    override func mouseDown(with event: NSEvent) {
        guard let model, !model.busy, model.image != nil, let renderer else { return }
        let p = point(event)
        guard imageRect.contains(p) else { return }
        window?.makeFirstResponder(self)
        cursorPoint = p
        let stroke = MarkStroke(tool:model.tool,diameter:model.brushSize/scale,block:model.blockSize,points:[imagePoint(p)],shape:model.brushShape,color:InkColor(NSColor(model.brushColor)),opacity:model.inkOpacity,blurRadius:model.blurRadius,lassoEffect:model.lassoEffect)
        activeStroke = stroke
        do {
            strokeBase = try renderer.snapshot()
            if stroke.tool != .lasso && stroke.tool != .line { try renderer.apply(stroke); try refreshSnapshot() }
            needsDisplay = true
        }
        catch { activeStroke = nil; model.errorMessage = error.localizedDescription }
    }
    override func mouseDragged(with event: NSEvent) {
        guard var stroke = activeStroke, let renderer else { return }
        let p = point(event); cursorPoint = p
        let next = imagePoint(p)
        if let last = stroke.points.last, hypot(next.x-last.x,next.y-last.y)<0.3 { return }
        if stroke.tool == .line { stroke.points = [stroke.points[0],next] }
        else { stroke.points.append(next) }
        activeStroke = stroke
        do {
            if stroke.tool != .lasso {
                if stroke.tool == .line || (stroke.tool == .solid && stroke.opacity < 1), let base = strokeBase {
                    renderer.restore(base)
                    try renderer.apply(stroke)
                } else { try renderer.apply(stroke,from:stroke.points.count-1) }
                try refreshSnapshot()
            }
            needsDisplay = true
        }
        catch { model?.errorMessage = error.localizedDescription }
    }
    override func mouseUp(with event: NSEvent) {
        if activeStroke?.tool == .lasso || activeStroke?.tool == .line { mouseDragged(with:event) }
        finishStroke()
    }
    private func refreshSnapshot() throws {
        if let image = try renderer?.snapshot() {
            displayed = NSImage(cgImage:image,size:CGSize(width:image.width,height:image.height)); needsDisplay = true
        }
    }
    func finishStroke() {
        guard let stroke = activeStroke, let renderer, let model else { return }
        activeStroke = nil; strokeBase = nil
        if stroke.tool == .line && stroke.points.count < 2 { needsDisplay = true; return }
        if stroke.tool == .lasso && stroke.points.count < 3 { needsDisplay = true; return }
        do {
            let rendered = try renderer.render((model.selected?.strokes ?? [])+[stroke])
            model.commit(stroke,rendered:rendered)
            seenRevision = model.revision
            displayed = NSImage(cgImage:rendered,size:CGSize(width:rendered.width,height:rendered.height))
            needsDisplay = true
        } catch { model.errorMessage = error.localizedDescription }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36,76: model?.markDone()
        case 123: model?.navigate(-1)
        case 124: model?.navigate(1)
        case 53:
            activeStroke = nil; strokeBase = nil; cursorPoint = nil
            if let strokes = model?.selected?.strokes, let rendered = try? renderer?.render(strokes) {
                displayed = NSImage(cgImage:rendered,size:CGSize(width:rendered.width,height:rendered.height))
            }
            needsDisplay = true
        default: super.keyDown(with:event)
        }
    }
    @objc func paste(_ sender: Any?) { model?.paste() }
    // Return false for ordinary scrolling so AppKit retains native panning.
    func handleScrollWheel(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let zooming = flags == .command
        let adjusting = flags == .option || flags == [.option, .shift]
        guard model?.pointerOverControls != true else { return false }
        guard zooming || adjusting else { wheelSetting = ""; wheelRemainder = 0; return false }
        guard let model, model.image != nil, !model.busy else { return true }
        // A trackpad's inertial tail must not continue changing tools after release.
        guard event.momentumPhase.isEmpty else { return true }
        // AppKit can translate Shift + vertical wheel into horizontal deltas.
        let vertical = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        let horizontal = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX
        let delta = vertical != 0 ? vertical : (flags.contains(.shift) ? horizontal : 0)
        let steps = event.hasPreciseScrollingDeltas ? delta / 12 : delta
        guard steps.isFinite, steps != 0 else { return true }
        if zooming {
            wheelSetting = ""; wheelRemainder = 0
            zoom(by: pow(1.12, max(-20, min(20, steps))), at: point(event))
            return true
        }
        let secondary = flags.contains(.shift)
        let setting = model.tool == .lasso ? (model.lassoEffect == .blur ? "blur" : "grain") : (model.tool == .mosaic && secondary) ? "grain" :
            (secondary ? (model.tool == .blur ? "blur" : "opacity") : "size")
        if wheelSetting != setting { wheelRemainder = 0; wheelSetting = setting }
        wheelRemainder += steps
        let ticks = wheelRemainder.rounded(.towardZero)
        guard ticks != 0 else { return true }
        wheelRemainder -= ticks
        switch setting {
        case "grain": model.blockSize = min(100, max(6, model.blockSize + ticks * 2))
        case "blur": model.blurRadius = min(60, max(2, model.blurRadius + ticks * 2))
        case "opacity": model.inkOpacity = min(1, max(0, model.inkOpacity + ticks * 0.05))
        default: model.brushSize = min(180, max(8, model.brushSize + ticks * 4))
        }
        updateGlassCursor()
        return true
    }
    func zoom(by factor: Double, at anchor: CGPoint) {
        guard let model, model.image != nil, !model.busy, factor.isFinite, factor > 0 else { return }
        finishStroke()
        let pixel = imagePoint(anchor)
        let clip = enclosingScrollView?.contentView
        let offset = CGPoint(x:anchor.x-(clip?.bounds.minX ?? 0), y:anchor.y-(clip?.bounds.minY ?? 0))
        model.zoom = min(8, max(0.05, scale * factor))
        arrange(in: enclosingScrollView?.contentSize ?? viewport)
        let newAnchor = CGPoint(x:imageRect.minX+pixel.x*scale, y:imageRect.minY+pixel.y*scale)
        if let clip {
            let proposed = CGRect(origin:CGPoint(x:newAnchor.x-offset.x,y:newAnchor.y-offset.y), size:clip.bounds.size)
            clip.scroll(to:clip.constrainBoundsRect(proposed).origin)
            enclosingScrollView?.reflectScrolledClipView(clip)
            cursorPoint = CGPoint(x:clip.bounds.minX+offset.x,y:clip.bounds.minY+offset.y)
        } else { cursorPoint = newAnchor }
    }
    override func magnify(with event: NSEvent) {
        zoom(by: max(0.01, 1+event.magnification), at: point(event))
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { finishStroke() }; super.viewWillMove(toWindow:newWindow) }
}

private final class GlassCursorView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
