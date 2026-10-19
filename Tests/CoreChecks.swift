// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
struct CoreChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("TuMa-check-"+UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let image = fixture()
        let source = root.appendingPathComponent("原图.png")
        try ImageCodec.png(image, to: source)
        let originalBytes = try Data(contentsOf: source)
        let decoded = try ImageCodec.decode(source)
        try check(decoded.width == 320 && decoded.height == 200, "decode full resolution")
        let renderer = try ImageRenderer(original: decoded)
        let solid = MarkStroke(tool:.solid,diameter:24,block:18,points:[MarkPoint(CGPoint(x:50,y:35)),MarkPoint(CGPoint(x:200,y:35))])
        let painted = try renderer.render([solid])
        let raw = pixel(painted,50,35)
        try check(raw[0]<3 && raw[1]<3 && raw[2]<3, "paint coordinates match top-left image coordinates")
        try check(pixel(painted,50,165) == pixel(decoded,50,165), "painting does not affect mirrored location")
        let mosaic = MarkStroke(tool:.mosaic,diameter:40,block:24,points:[MarkPoint(CGPoint(x:60,y:70)),MarkPoint(CGPoint(x:250,y:70))])
        let marked = try renderer.render([mosaic])
        try check(pixel(marked,80,70) != pixel(decoded,80,70), "mosaic changes source pixels")
        try check(pixel(marked,5,5) == pixel(decoded,5,5), "mosaic preserves outside pixels")
        let restored = try renderer.render([])
        try check(pixels(restored) == pixels(decoded), "empty history restores image exactly")
        let export = root.appendingPathComponent("打码.png")
        try ImageCodec.png(painted,to:export)
        let output = try ImageCodec.decode(export)
        try check(output.width == 320 && output.height == 200, "PNG export retains original dimensions")
        try check(pixel(output,50,35)[0]<3, "exported PNG contains flattened redaction")
        // EXIF orientation 6 rotates 320x200 into 200x320 before editing.
        let rotated = root.appendingPathComponent("orientation.jpg")
        let dest = CGImageDestinationCreateWithURL(rotated as CFURL,UTType.jpeg.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(dest,image,[kCGImagePropertyOrientation:6] as CFDictionary)
        try check(CGImageDestinationFinalize(dest), "create orientation fixture")
        let oriented = try ImageCodec.decode(rotated)
        try check(oriented.width == 200 && oriented.height == 320, "camera orientation normalized")
        let workspace = root.appendingPathComponent("workspace")
        let model = WorkspaceModel(root:workspace)
        model.importURLs([source,source])
        try await wait { !model.busy && model.image != nil }
        try check(model.photos.count == 2, "batch import permits duplicate source names")
        model.commit(solid,rendered:painted)
        try check(model.canUndo && !model.selected!.done, "commit enables undo and requires confirmation")
        model.undo()
        try check(model.selected!.strokes.isEmpty && model.canRedo, "undo preserves redo history")
        model.redo()
        try check(model.selected!.strokes.count == 1 && !model.canRedo, "redo restores complete stroke")
        let first = model.selection
        model.markDone()
        try await wait { model.image != nil }
        try check(model.completed == 1 && model.selection != first, "confirm advances selection")
        model.saveNow()
        let reopened = WorkspaceModel(root:workspace)
        try await wait { reopened.image != nil }
        try check(reopened.photos.count == 2 && reopened.completed == 1 && reopened.photos[0].strokes == [solid], "workspace restores originals, history and completion")
        let board = NSPasteboard.withUniqueName()
        board.setData(originalBytes,forType:.png)
        reopened.paste(from:board)
        try await wait { !reopened.busy && reopened.photos.count == 3 && reopened.image != nil }
        try check(reopened.selected!.name.hasPrefix("粘贴图片"), "paste imports raw clipboard PNG and selects it")
        board.clearContents(); board.writeObjects([source as NSURL])
        reopened.paste(from:board)
        try await wait { !reopened.busy && reopened.photos.count == 4 && reopened.image != nil }
        try check(reopened.selected!.name == "原图.png", "Finder file URL paste imports file")
        board.releaseGlobally()
        try check(try Data(contentsOf:source) == originalBytes, "source file is unchanged")
        let transparentContext = CGContext(data:nil,width:100,height:100,bitsPerComponent:8,bytesPerRow:400,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let transparent = transparentContext.makeImage()!
        let dot = MarkStroke(tool:.solid,diameter:20,block:10,points:[MarkPoint(CGPoint(x:50,y:50))])
        let alphaResult = try ImageRenderer(original:transparent).render([dot])
        try check(pixel(alphaResult,0,0)[3] == 0, "export preserves unpainted transparency")
        try check(pixel(alphaResult,50,50) == [0,0,0,255], "single-click solid brush is fully opaque")
        let zipFolder = root.appendingPathComponent("中文图片")
        try fm.createDirectory(at:zipFolder,withIntermediateDirectories:true)
        try ImageCodec.png(painted,to:zipFolder.appendingPathComponent("打码图片.png"))
        let zipURL = root.appendingPathComponent("中文压缩包.zip")
        try ZipArchive.write(folder:zipFolder,to:zipURL)
        let archiveBytes = try Data(contentsOf:zipURL)
        try check(archiveBytes[6] == 0 && archiveBytes[7] == 8, "ZIP explicitly declares UTF-8 filenames")
        let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/unzip")
        process.arguments = ["-t",zipURL.path]; process.standardOutput = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        try check(process.terminationStatus == 0, "ZIP passes independent CRC integrity check")
        let red = InkColor(red:1,green:0.15,blue:0.2)
        let squareDot = MarkStroke(tool:.solid,diameter:20,block:12,points:[MarkPoint(CGPoint(x:50,y:50))],shape:.square,color:red)
        let squareResult = try ImageRenderer(original:transparent).render([squareDot])
        try check(pixel(squareResult,58,58)[3] == 255, "square brush fills corners outside the round brush")
        let corner = pixel(squareResult,58,58)
        try check(corner[0] > 250 && corner[1] < 60 && corner[2] < 65, "brush color is applied as opaque selected RGB")
        try check(pixel(squareResult,62,50)[3] == 0, "square brush preserves pixels outside its footprint")
        let diagonal = MarkStroke(tool:.solid,diameter:12,block:12,points:[MarkPoint(CGPoint(x:20,y:20)),MarkPoint(CGPoint(x:80,y:80))],shape:.square)
        let diagonalResult = try ImageRenderer(original:transparent).render([diagonal])
        try check(pixel(diagonalResult,50,40)[3] == 255 && pixel(diagonalResult,50,50)[3] == 255, "square brush sweeps continuously across sparse diagonal samples")
        let lasso = MarkStroke(tool:.lasso,diameter:20,block:24,points:[MarkPoint(CGPoint(x:20,y:25)),MarkPoint(CGPoint(x:150,y:25)),MarkPoint(CGPoint(x:150,y:110)),MarkPoint(CGPoint(x:20,y:110))])
        let lassoResult = try ImageRenderer(original:decoded).render([lasso])
        try check(pixel(lassoResult,80,70) != pixel(decoded,80,70), "lasso fills its entire interior with mosaic")
        try check(pixel(lassoResult,200,70) == pixel(decoded,200,70), "lasso preserves pixels outside the polygon")
        let closedLasso = MarkStroke(tool:.lasso,diameter:20,block:24,points:lasso.points+[lasso.points[0]])
        try check(pixels(try ImageRenderer(original:decoded).render([closedLasso])) == pixels(lassoResult), "lasso automatically closes an open drawn boundary")
        let serialized = try JSONEncoder().encode(squareDot)
        var legacy = try JSONSerialization.jsonObject(with:serialized) as! [String:Any]
        legacy.removeValue(forKey:"shape"); legacy.removeValue(forKey:"color"); legacy.removeValue(forKey:"opacity"); legacy.removeValue(forKey:"blurRadius")
        let legacyStroke = try JSONDecoder().decode(MarkStroke.self,from:JSONSerialization.data(withJSONObject:legacy))
        try check(legacyStroke.shape == .round && legacyStroke.color == .black && legacyStroke.opacity == 1 && legacyStroke.blurRadius == 16, "old workspaces decode as round black strokes")
        let roundTrip = try JSONDecoder().decode(MarkStroke.self,from:serialized)
        try check(roundTrip == squareDot, "new brush shape and color survive serialization")
        let lassoRoundTrip = try JSONDecoder().decode(MarkStroke.self,from:JSONEncoder().encode(lasso))
        try check(lassoRoundTrip == lasso, "lasso path survives workspace serialization")
        let blurLasso = MarkStroke(tool: .lasso, diameter: 20, block: 24, points: lasso.points, blurRadius: 12, lassoEffect: .blur)
        let blurLassoResult = try ImageRenderer(original: decoded).render([blurLasso])
        try check(pixel(blurLassoResult, 80, 100) != pixel(decoded, 80, 100), "Gaussian lasso blurs the interior of its polygon")
        try check(pixel(blurLassoResult, 200, 100) == pixel(decoded, 200, 100), "Gaussian lasso preserves pixels outside the polygon")
        let fullBlur = MarkStroke(tool: .blur, diameter: 1000, block: 24, points: [MarkPoint(CGPoint(x: 160, y: 100))], blurRadius: 12)
        let fullBlurResult = try ImageRenderer(original: decoded).render([fullBlur])
        try check(pixel(blurLassoResult, 80, 100) == pixel(fullBlurResult, 80, 100), "Gaussian lasso uses the same full-resolution blur as the Gaussian brush")
        let lassoExport = root.appendingPathComponent("Gaussian-lasso.png")
        try ImageCodec.png(blurLassoResult, to: lassoExport)
        let exportedLasso = try ImageCodec.decode(lassoExport)
        try check(exportedLasso.width == decoded.width && exportedLasso.height == decoded.height && pixels(exportedLasso) == pixels(blurLassoResult), "Gaussian lasso export retains dimensions and flattened pixels")
        try check(try JSONDecoder().decode(MarkStroke.self, from: JSONEncoder().encode(blurLasso)) == blurLasso, "lasso effect and strength survive serialization")
        var oldLasso = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lasso)) as! [String: Any]
        oldLasso.removeValue(forKey: "lassoEffect")
        let oldDecodedLasso = try JSONDecoder().decode(MarkStroke.self, from: JSONSerialization.data(withJSONObject: oldLasso))
        try check(oldDecodedLasso.lassoEffect == .mosaic && pixels(try ImageRenderer(original: decoded).render([oldDecodedLasso])) == pixels(lassoResult), "existing lasso strokes remain mosaic without a new effect field")
        let blackCover = MarkStroke(tool: .solid, diameter: 1000, block: 24, points: [MarkPoint(CGPoint(x: 160, y: 100))])
        let protectedLasso = try ImageRenderer(original: decoded).render([blackCover, blurLasso])
        try check(pixel(protectedLasso, 80, 100).prefix(3).allSatisfy { $0 < 3 }, "Gaussian lasso respects earlier redactions in the composite")
        // Exercise the real canvas event handlers in an off-screen test window.
        reopened.tool = .lasso
        let testWindow = NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:600),styleMask:.borderless,backing:.buffered,defer:false)
        testWindow.isReleasedWhenClosed = false
        let canvas = DrawingCanvas(frame:NSRect(x:0,y:0,width:800,height:600))
        testWindow.contentView = canvas; canvas.model = reopened; canvas.sync(); canvas.arrange(in:CGSize(width:800,height:600))
        func mouse(_ type: NSEvent.EventType, _ imagePoint: CGPoint) -> NSEvent {
            let viewPoint = CGPoint(x:240+imagePoint.x,y:170+imagePoint.y)
            return NSEvent.mouseEvent(with:type,location:canvas.convert(viewPoint,to:nil),modifierFlags:[],timestamp:0,windowNumber:testWindow.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        let countBefore = reopened.selected!.strokes.count
        canvas.mouseDown(with:mouse(.leftMouseDown,CGPoint(x:20,y:25)))
        canvas.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:150,y:25)))
        canvas.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:150,y:110)))
        canvas.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:20,y:110)))
        try check(reopened.selected!.strokes.count == countBefore, "lasso preview does not commit while dragging")
        canvas.mouseUp(with:mouse(.leftMouseUp,CGPoint(x:20,y:110)))
        try check(reopened.selected!.strokes.count == countBefore+1 && reopened.selected!.strokes.last!.tool == .lasso, "mouse release commits one filled lasso stroke")
        reopened.undo();try check(reopened.selected!.strokes.count == countBefore, "lasso is undone as a single operation")
        reopened.redo();try check(reopened.selected!.strokes.last!.tool == .lasso, "lasso redo restores the region")
        canvas.mouseDown(with:mouse(.leftMouseDown,CGPoint(x:30,y:30)))
        canvas.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:100,y:30)))
        let escape = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:testWindow.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
        canvas.keyDown(with:escape)
        canvas.mouseUp(with:mouse(.leftMouseUp,CGPoint(x:100,y:100)))
        try check(reopened.selected!.strokes.count == countBefore+1, "Escape cancels a pending lasso")
        reopened.lassoEffect = .blur; reopened.blurRadius = 20
        canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x:20,y:25)))
        reopened.lassoEffect = .mosaic
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x:150,y:25)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x:150,y:110)))
        canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x:20,y:110)))
        try check(reopened.selected!.strokes.count == countBefore+2 && reopened.selected!.strokes.last!.lassoEffect == .blur && reopened.selected!.strokes.last!.blurRadius == 20, "Gaussian lasso commits one operation using the effect captured when drawing starts")
        reopened.undo()
        try check(reopened.selected!.strokes.count == countBefore+1, "Gaussian lasso undoes as one operation")
        reopened.redo()
        try check(reopened.selected!.strokes.last!.lassoEffect == .blur, "Gaussian lasso redo preserves its effect")
        reopened.saveNow()
        let restoredLassoWorkspace = WorkspaceModel(root: workspace)
        try check(restoredLassoWorkspace.selected!.strokes.last!.lassoEffect == .blur && restoredLassoWorkspace.selected!.strokes.last!.blurRadius == 20, "reopening the workspace preserves Gaussian lasso effect and strength")
        let flatLine = MarkStroke(tool:.line,diameter:20,block:12,points:[MarkPoint(CGPoint(x:20,y:50)),MarkPoint(CGPoint(x:80,y:50))],color:red)
        let lineResult = try ImageRenderer(original:transparent).render([flatLine])
        try check(pixel(lineResult,15,50)[3] == 0 && pixel(lineResult,85,50)[3] == 0, "line has flat endpoints without round or extended caps")
        try check(pixel(lineResult,25,58)[3] == 255 && pixel(lineResult,50,62)[3] == 0, "line honors rectangular footprint and width")
        try check(pixel(lineResult,50,50)[0] > 250 && pixel(lineResult,50,50)[1] < 60, "line uses the selected color")
        var halfLine = flatLine; halfLine.opacity = 0.5
        let halfResult = try ImageRenderer(original:transparent).render([halfLine])
        try check(abs(Int(pixel(halfResult,50,50)[3])-128)<=1, "line opacity is composited correctly")
        let retraced = MarkStroke(tool:.solid,diameter:20,block:12,points:[MarkPoint(CGPoint(x:20,y:50)),MarkPoint(CGPoint(x:80,y:50)),MarkPoint(CGPoint(x:20,y:50))],opacity:0.5)
        let retracedResult = try ImageRenderer(original:transparent).render([retraced])
        try check(abs(Int(pixel(retracedResult,50,50)[3])-128)<=1, "brush opacity stays uniform across a self-overlapping stroke")
        let persistedLine = try JSONDecoder().decode(MarkStroke.self,from:JSONEncoder().encode(halfLine))
        try check(persistedLine == halfLine, "line endpoints and opacity survive workspace serialization")
        reopened.tool = .line; reopened.inkOpacity = 0.4; canvas.sync()
        let beforeLine = reopened.selected!.strokes.count
        canvas.mouseDown(with:mouse(.leftMouseDown,CGPoint(x:20,y:140)))
        canvas.mouseDragged(with:mouse(.leftMouseDragged,CGPoint(x:80,y:160)))
        canvas.mouseUp(with:mouse(.leftMouseUp,CGPoint(x:140,y:140)))
        let lastLine = reopened.selected!.strokes.last!
        try check(reopened.selected!.strokes.count == beforeLine+1 && lastLine.tool == .line && lastLine.points.count == 2, "dragged line commits only its start and final endpoint")
        try check(lastLine.points.last!.y == 140 && lastLine.opacity == 0.4, "line preview follows the endpoint and preserves current opacity")
        let lens = canvas.subviews.compactMap { $0 as? NSGlassEffectView }.first!
        try check(!lens.isHidden && lens.style == .clear && lens.cornerRadius == lens.frame.width/2, "canvas cursor uses an actual circular system glass effect")
        try check(lens.hitTest(CGPoint(x:lens.bounds.midX,y:lens.bounds.midY)) == nil, "glass cursor does not intercept drawing input")
        let firstControl = UUID(), secondControl = UUID()
        reopened.setControlHover(firstControl,inside:true)
        try check(lens.isHidden && reopened.pointerOverControls, "entering a glass control immediately hides the painting cursor")
        reopened.setControlHover(secondControl,inside:true)
        reopened.setControlHover(firstControl,inside:false)
        try check(lens.isHidden && reopened.pointerOverControls, "crossing overlapping glass controls preserves the system pointer")
        reopened.setControlHover(secondControl,inside:false)
        try check(!lens.isHidden && !reopened.pointerOverControls, "leaving glass controls restores the canvas cursor")
        testWindow.contentView = nil
        let scroll = CanvasScrollView(frame:NSRect(x:0,y:0,width:800,height:600))
        scroll.documentView = scroll.canvas
        testWindow.contentView = scroll
        scroll.canvas.model = reopened; scroll.canvas.sync(); scroll.layoutCanvas()
        func wheel(_ flags: CGEventFlags, _ amount: Int32 = 1, precise: Bool = false) -> NSEvent {
            let cg = CGEvent(scrollWheelEvent2Source:nil,units:precise ? .pixel : .line,wheelCount:1,wheel1:amount,wheel2:0,wheel3:0)!
            cg.flags = flags
            return NSEvent(cgEvent:cg)!
        }
        reopened.tool = .line; reopened.brushSize = 48; reopened.inkOpacity = 0.4
        let savedStrokes = reopened.selected!.strokes
        reopened.setControlHover(firstControl,inside:true)
        try check(!scroll.canvas.handleScrollWheel(wheel(.maskAlternate)) && reopened.brushSize == 48, "wheel over a glass control does not change canvas settings")
        reopened.setControlHover(firstControl,inside:false)
        let up = wheel(.maskAlternate)
        try check(up.deltaY > 0 && scroll.canvas.handleScrollWheel(up), "native Option wheel event is handled by canvas")
        try check(reopened.brushSize == 52, "Option wheel increases line width by four pixels")
        scroll.scrollWheel(with:wheel(.maskAlternate,-1))
        try check(reopened.brushSize == 48, "reverse wheel decreases line width through scroll view")
        scroll.scrollWheel(with:wheel([.maskAlternate,.maskShift]))
        try check(abs(reopened.inkOpacity-0.45)<0.0001, "Option Shift wheel adjusts line opacity")
        reopened.tool = .solid
        scroll.scrollWheel(with:wheel([.maskAlternate,.maskShift],100))
        try check(reopened.inkOpacity == 1, "brush opacity clamps at one hundred percent")
        scroll.scrollWheel(with:wheel([.maskAlternate,.maskShift],-100))
        try check(reopened.inkOpacity == 0, "brush opacity clamps at zero percent")
        reopened.brushSize = 179
        scroll.scrollWheel(with:wheel(.maskAlternate,100))
        try check(reopened.brushSize == 180, "width is bounded by the settings slider maximum")
        scroll.scrollWheel(with:wheel(.maskAlternate,-100))
        try check(reopened.brushSize == 8, "width is bounded by the settings slider minimum")
        reopened.tool = .mosaic; reopened.blockSize = 24
        scroll.scrollWheel(with:wheel([.maskAlternate,.maskShift]))
        try check(reopened.blockSize == 26, "mosaic secondary wheel adjusts grain")
        reopened.tool = .lasso
        scroll.scrollWheel(with:wheel(.maskAlternate))
        try check(reopened.blockSize == 28, "lasso primary wheel adjusts grain instead of hidden brush size")
        reopened.lassoEffect = .blur; reopened.blurRadius = 16
        scroll.scrollWheel(with: wheel(.maskAlternate))
        try check(reopened.blurRadius == 18 && reopened.blockSize == 28, "Gaussian lasso wheel adjusts blur strength instead of mosaic grain")
        reopened.lassoEffect = .mosaic
        try check(!scroll.canvas.handleScrollWheel(wheel([])), "ordinary wheel remains available for native panning")
        reopened.tool = .solid; reopened.brushSize = 48
        for _ in 0..<12 { _ = scroll.canvas.handleScrollWheel(wheel(.maskAlternate,1,precise:true)) }
        try check(reopened.brushSize == 52, "small precise trackpad deltas accumulate without dropping input")
        let momentum = wheel(.maskAlternate).cgEvent!
        momentum.setIntegerValueField(.scrollWheelEventMomentumPhase,value:1)
        scroll.scrollWheel(with:NSEvent(cgEvent:momentum)!)
        try check(reopened.brushSize == 52, "trackpad momentum cannot continue changing brush size")
        reopened.busy = true
        scroll.scrollWheel(with:wheel(.maskAlternate))
        try check(reopened.brushSize == 52, "busy workspace blocks wheel changes")
        reopened.busy = false; reopened.zoom = 1; scroll.layoutCanvas()
        scroll.scrollWheel(with:wheel(.maskCommand))
        try check(abs(reopened.zoom-1.12)<0.0001, "Command wheel zooms the canvas")
        scroll.canvas.zoom(by:1000,at:CGPoint(x:400,y:300))
        try check(reopened.zoom == 8, "canvas zoom clamps at eight hundred percent")
        // At 4x and 8x, both dimensions can scroll; verify the pixel under the pointer.
        reopened.zoom = 4; scroll.layoutCanvas()
        scroll.contentView.scroll(to:CGPoint(x:200,y:180))
        let anchor = CGPoint(x:500,y:400)
        let offset = CGPoint(x:anchor.x-scroll.contentView.bounds.minX,y:anchor.y-scroll.contentView.bounds.minY)
        scroll.canvas.zoom(by:2,at:anchor)
        // For this fixture: image origin at 4x=(36,80), at 8x=(36,80).
        let expected = CGPoint(x:36+(anchor.x-36)*2-offset.x,y:80+(anchor.y-80)*2-offset.y)
        try check(abs(scroll.contentView.bounds.minX-expected.x)<1 && abs(scroll.contentView.bounds.minY-expected.y)<1, "zoom preserves the image pixel under the pointer when scrolling allows")
        scroll.canvas.zoom(by:0.00001,at:anchor)
        try check(reopened.zoom == 0.05, "canvas zoom clamps at five percent")
        try check(reopened.selected!.strokes == savedStrokes, "wheel settings and zoom leave existing artwork unchanged")
        testWindow.contentView = nil
        let queue = WorkspaceModel(root:root.appendingPathComponent("queue"))
        queue.importURLs([source, source, source, source, source])
        try await wait { !queue.busy && queue.image != nil }
        let orderedIDs = queue.photos.map(\.id)
        queue.selectPhotos([orderedIDs[0], orderedIDs[2]], focus:orderedIDs[2])
        try check(queue.selectedPhotoIDs == [orderedIDs[0], orderedIDs[2]] && queue.selection == orderedIDs[2], "multiple selection retains all IDs and a distinct focused canvas")
        queue.movePhotos(queue.selectedPhotoIDs, before:5)
        try check(queue.photos.map(\.id) == [orderedIDs[1],orderedIDs[3],orderedIDs[4],orderedIDs[0],orderedIDs[2]], "dragging nonadjacent cards preserves their relative order")
        try check(queue.selection == orderedIDs[2] && queue.selectedPhotoIDs.count == 2, "reordering preserves focus and multiple selection")
        let queueRestored = WorkspaceModel(root:queue.root)
        try check(queueRestored.photos.map(\.id) == queue.photos.map(\.id), "dragged queue order persists across reopening")
        queue.movePhotos([orderedIDs[0],orderedIDs[2]], before:0)
        try check(queue.photos.map(\.id) == [orderedIDs[0],orderedIDs[2],orderedIDs[1],orderedIDs[3],orderedIDs[4]], "cards can move from bottom to top")
        let unchanged = queue.photos.map(\.id)
        queue.movePhotos([orderedIDs[0],orderedIDs[2]], before:1)
        try check(queue.photos.map(\.id) == unchanged, "dropping inside the dragged group keeps its order intact")
        queue.busy = true
        queue.movePhotos([orderedIDs[0]], before:5)
        queue.selectPhotos([orderedIDs[4]])
        try check(queue.photos.map(\.id) == unchanged && queue.selectedPhotoIDs.count == 2, "busy import or export blocks selection and reorder mutations")
        queue.busy = false
        queue.removeSelected()
        try check(queue.photos.map(\.id) == [orderedIDs[1],orderedIDs[3],orderedIDs[4]] && queue.selection == orderedIDs[1], "batch removal removes selected cards and focuses the nearest survivor")
        try check(FileManager.default.fileExists(atPath:queue.originals.appendingPathComponent(queueRestored.photos[0].storedName).path), "queue removal retains original workspace image copies")
        queue.selectPhotos([])
        queue.removeSelected()
        try check(queue.photos.count == 3 && queue.selection == orderedIDs[1], "clearing the selection retains the canvas and cannot remove an unselected image")
        queue.selection = orderedIDs[4]
        try check(queue.selectedPhotoIDs == [orderedIDs[4]], "single-image navigation resets sidebar multiple selection")
        let blur = MarkStroke(tool:.blur,diameter:90,block:24,points:[MarkPoint(CGPoint(x:160,y:110))],blurRadius:12)
        let blurResult = try ImageRenderer(original:decoded).render([blur])
        try check(pixel(blurResult,160,110) != pixel(decoded,160,110), "Gaussian brush smooths source detail inside its footprint")
        try check(pixel(blurResult,10,10) == pixel(decoded,10,10), "Gaussian blur preserves pixels outside the brush")
        let blurExport = root.appendingPathComponent("Gaussian-export.png")
        try ImageCodec.png(blurResult,to:blurExport)
        let exportedBlur = try ImageCodec.decode(blurExport)
        try check(exportedBlur.width == decoded.width && exportedBlur.height == decoded.height && pixel(exportedBlur,160,110) == pixel(blurResult,160,110), "Gaussian export retains full resolution and flattened blur pixels")
        var wideBlur = blur; wideBlur.diameter = 1000; wideBlur.blurRadius = 2
        let weak = try ImageRenderer(original:decoded).render([wideBlur])
        wideBlur.blurRadius = 32
        let strong = try ImageRenderer(original:decoded).render([wideBlur])
        func energy(_ image:CGImage) -> Int {
            let bytes = pixels(image); var sum = 0
            for x in 80..<240 { sum += abs(Int(bytes[(110*image.width+x)*4])-Int(bytes[(110*image.width+x+1)*4])) }
            return sum
        }
        try check(energy(strong)<energy(weak), "higher Gaussian strength removes more high frequency detail")
        try check(pixel(strong,0,0)[3] == 255 && pixel(strong,319,199)[3] == 255, "clamped Gaussian edges do not introduce transparency")
        let cover = MarkStroke(tool:.solid,diameter:100,block:24,points:[MarkPoint(CGPoint(x:20,y:100)),MarkPoint(CGPoint(x:300,y:100))])
        var smallBlur = blur; smallBlur.blurRadius = 4
        let covered = try ImageRenderer(original:decoded).render([cover,smallBlur])
        try check(pixel(covered,160,100).prefix(3).allSatisfy { $0 < 5 }, "Gaussian blur uses the composited image and preserves earlier solid redactions")
        let decodedBlur = try JSONDecoder().decode(MarkStroke.self,from:JSONEncoder().encode(blur))
        try check(decodedBlur == blur, "Gaussian radius and tool survive workspace serialization")
        let incremental = try ImageRenderer(original:decoded)
        var draggedBlur = blur; draggedBlur.points = [MarkPoint(CGPoint(x:90,y:110))]
        try incremental.apply(draggedBlur)
        draggedBlur.points.append(MarkPoint(CGPoint(x:220,y:110)))
        try incremental.apply(draggedBlur,from:1)
        let committedBlur = try ImageRenderer(original:decoded).render([draggedBlur])
        try check(pixel(try incremental.snapshot(),150,110) == pixel(committedBlur,150,110), "Gaussian brush preview and committed stroke use the same pre-stroke image")
        reopened.tool = .blur; reopened.blurRadius = 16
        scroll.scrollWheel(with:wheel([.maskAlternate,.maskShift]))
        try check(reopened.blurRadius == 18, "Gaussian secondary wheel adjusts blur strength")
        scroll.scrollWheel(with:wheel([.maskAlternate,.maskShift],100))
        try check(reopened.blurRadius == 60, "Gaussian wheel strength clamps to the slider range")
        let pickerHost = ToolPickerHost(frame:NSRect(x:0,y:0,width:ToolPicker.width,height:ToolPicker.height))
        pickerHost.layoutSubtreeIfNeeded()
        let controlFrame = pickerHost.control.frame
        let fitting = pickerHost.control.fittingSize
        var stableFrames = true
        for index in MarkTool.allCases.indices {
            pickerHost.control.selectedSegment = index
            pickerHost.needsLayout = true; pickerHost.layoutSubtreeIfNeeded()
            stableFrames = stableFrames && pickerHost.control.frame == controlFrame && pickerHost.control.fittingSize == fitting
        }
        try check(stableFrames && controlFrame.width == ToolPicker.controlWidth, "all five native tool selections retain the same control frame and fitting size")
        try check(MarkTool.allCases.indices.allSatisfy { pickerHost.control.width(forSegment:$0) == ToolPicker.slotWidth && pickerHost.control.image(forSegment:$0)?.size == NSSize(width:20,height:20) }, "tool symbols and selection slots have fixed equal dimensions")
        try check(TitlebarDoubleClickAction.preference("Maximize") == .fill, "titlebar honors the system Fill preference")
        try check(TitlebarDoubleClickAction.preference("None") == .none, "titlebar honors the system no-action preference")
        try check(TitlebarDoubleClickAction.preference("Minimize") == .minimize, "titlebar honors the system minimize preference")
        try check(TitlebarDoubleClickAction.preference("Zoom") == .zoom, "titlebar preserves standard AppKit zoom preference")
        try check(!canvas.mouseDownCanMoveWindow && !scroll.mouseDownCanMoveWindow, "canvas input cannot start a background window drag")
        let visible = NSScreen.screens[0].visibleFrame
        let windowCheck = NSWindow(contentRect:NSRect(x:visible.minX+100,y:visible.minY+100,width:600,height:400),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
        windowCheck.isReleasedWhenClosed = false
        let savedFrame = windowCheck.frame
        let nativeBehavior = WindowBehaviorView()
        nativeBehavior.performDoubleClick(.fill,in:windowCheck)
        try check(windowCheck.frame == windowCheck.screen!.visibleFrame, "titlebar Fill uses the current screen usable frame")
        nativeBehavior.performDoubleClick(.fill,in:windowCheck)
        try check(windowCheck.frame == savedFrame, "a second titlebar Fill restores the previous window frame")
        nativeBehavior.performDoubleClick(.none,in:windowCheck)
        try check(windowCheck.frame == savedFrame, "no-action titlebar preference leaves geometry unchanged")
        windowCheck.close()
        let sidebarCoordinator = PhotoSidebar.Coordinator(reopened)
        let sidebarScroll = PhotoSidebar.makeScrollView(coordinator: sidebarCoordinator)
        let sidebarCollection = sidebarCoordinator.collection!
        let sidebarWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
        sidebarWindow.isReleasedWhenClosed = false
        sidebarWindow.contentView = sidebarScroll
        sidebarCoordinator.refresh()
        for width: CGFloat in [300, 190, 250, 210, 300] {
            sidebarWindow.setContentSize(NSSize(width: width, height: 500))
            // Reproduce AppKit resizing the document before NSScrollView.layout.
            sidebarCollection.setFrameSize(NSSize(width: sidebarScroll.contentSize.width, height: 500))
            sidebarScroll.needsLayout = true
            sidebarScroll.layoutSubtreeIfNeeded()
            sidebarCollection.layoutSubtreeIfNeeded()
            let cardFrame = sidebarCollection.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
            try check(abs(cardFrame.width - (sidebarScroll.contentSize.width - 20)) < 0.5 && cardFrame.maxX <= sidebarScroll.contentSize.width, "sidebar cards reflow within viewport at width \(Int(width))")
        }
        let card = sidebarCollection.item(at: IndexPath(item: 0, section: 0)) as! PhotoCardItem
        let cardRoot = card.view as! PhotoCardRootView
        card.isSelected = false
        card.highlightState = .forSelection
        try check(!card.isSelected && cardRoot.showsSelection && (cardRoot.layer?.backgroundColor?.alpha ?? 0) > 0, "marquee paints gray before committing the selection")
        card.highlightState = .none
        try check(!cardRoot.showsSelection, "leaving marquee restores an unselected card immediately")
        card.isSelected = true
        card.highlightState = .forDeselection
        try check(card.isSelected && !cardRoot.showsSelection, "marquee deselection previews before mouse release")
        card.highlightState = .none
        try check(cardRoot.showsSelection, "ending preview restores committed selection")
        sidebarWindow.close()
        let toolbarButton = NSView(frame: .zero)
        toolbarButton.setAccessibilityRole(.button)
        let toolbarGlyph = NSView(frame: .zero)
        toolbarButton.addSubview(toolbarGlyph)
        try check(WindowBehaviorView.isInteractiveTitlebarView(toolbarGlyph), "sidebar toolbar button glyph cannot be intercepted as a window drag")
        let nativeButton = NSButton()
        let nativeGlyph = NSView(frame: .zero)
        nativeButton.addSubview(nativeGlyph)
        try check(WindowBehaviorView.isInteractiveTitlebarView(nativeGlyph), "native control descendants retain their mouse input")
        let spacer = NSView(frame: .zero)
        spacer.setAccessibilityRole(.group)
        try check(!WindowBehaviorView.isInteractiveTitlebarView(spacer), "noninteractive toolbar spacers still permit native window dragging")
        try check(pickerHost.control.controlSize == .large && pickerHost.contentView != nil && !pickerHost.clipsToBounds, "native tool picker uses a single glass container and leaves room for system press feedback")
        try check(abs(controlFrame.minX - (pickerHost.bounds.width - controlFrame.maxX)) < 0.5 && abs(controlFrame.minY - (pickerHost.bounds.height - controlFrame.maxY)) < 0.5, "expanded tool selection retains equal horizontal and vertical margins")
        if #available(macOS 27.0, *) {
            try check(pickerHost.responds(to: NSSelectorFromString("effectIsInteractive")) && (pickerHost.value(forKey: "effectIsInteractive") as? Bool) == true, "macOS 27 native interactive glass is enabled")
        }
        let chromeWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 520), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        chromeWindow.isReleasedWhenClosed = false
        WindowBehaviorView.configureChrome(in: chromeWindow)
        try check(chromeWindow.titlebarAppearsTransparent && chromeWindow.titlebarSeparatorStyle == .none, "canvas titlebar stays transparent without a separator")
        let toolbarDelegate = ToolbarChecksDelegate()
        let checkToolbar = NSToolbar(identifier: "input-check")
        checkToolbar.delegate = toolbarDelegate
        chromeWindow.toolbar = checkToolbar
        checkToolbar.insertItem(withItemIdentifier: toolbarDelegate.item.itemIdentifier, at: 0)
        chromeWindow.contentView?.superview?.layoutSubtreeIfNeeded()
        let itemView = toolbarDelegate.item.view!
        let itemPoint = itemView.convert(NSPoint(x: itemView.bounds.midX, y: itemView.bounds.midY), to: nil)
        try check(WindowBehaviorView.isInsideToolbarItem(itemPoint, in: chromeWindow), "custom SwiftUI-style toolbar groups are protected by actual item bounds")
        try check(!WindowBehaviorView.isInsideToolbarItem(NSPoint(x: 0, y: 0), in: chromeWindow), "toolbar geometry protection does not cover the canvas")
        let menuView = NSView()
        menuView.setAccessibilityRole(.menuButton)
        try check(WindowBehaviorView.isInteractiveTitlebarView(menuView), "menu-button accessibility role retains mouse input")
        chromeWindow.close()
        print("ALL 133 CHECKS PASSED (macOS 27)")
    }
    static func check(_ condition: Bool, _ name: String) throws {
        guard condition else { throw NSError(domain:"TuMaTests",code:1,userInfo:[NSLocalizedDescriptionKey:name]) }
        print("PASS: \(name)")
    }
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<300 { if condition() { return }; try await Task.sleep(for:.milliseconds(50)) }
        throw NSError(domain:"TuMaTests",code:2,userInfo:[NSLocalizedDescriptionKey:"async operation timed out"])
    }
    static func fixture() -> CGImage {
        let ctx = CGContext(data:nil,width:320,height:200,bitsPerComponent:8,bytesPerRow:320*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red:0.9,green:0.2,blue:0.1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:320,height:200))
        for x in stride(from:0,to:320,by:4) { ctx.setFillColor(CGColor(red:Double(x%17)/17,green:0.6,blue:0.8,alpha:1));ctx.fill(CGRect(x:x,y:90,width:2,height:80)) }
        return ctx.makeImage()!
    }
    static func pixels(_ image: CGImage) -> [UInt8] {
        let ctx = CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        return Array(UnsafeBufferPointer(start:ctx.data!.assumingMemoryBound(to:UInt8.self),count:image.width*image.height*4))
    }
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let bytes = pixels(image), offset=(y*image.width+x)*4
        return Array(bytes[offset..<offset+4])
    }
}

@MainActor final class ToolbarChecksDelegate: NSObject, NSToolbarDelegate {
    let item: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("custom-menu"))
        item.view = NSView(frame: NSRect(x: 0, y: 0, width: 48, height: 36))
        item.view?.setAccessibilityRole(.group)
        return item
    }()
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [item.itemIdentifier] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { item }
}
