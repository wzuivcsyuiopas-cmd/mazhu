// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum MarkTool: String, Codable, CaseIterable, Identifiable {
    case mosaic, solid, lasso, line, blur
    var id: String { rawValue }
    var title: String {
        switch self { case .mosaic: return "马赛克"; case .solid: return "画笔"; case .lasso: return "圈选"; case .line: return "直线"; case .blur: return "高斯模糊" }
    }
    var symbol: String {
        switch self { case .mosaic: return "square.grid.3x3.fill"; case .solid: return "paintbrush.pointed.fill"; case .lasso: return "lasso"; case .line: return "line.diagonal"; case .blur: return "drop.halffull" }
    }
}
enum BrushShape: String, Codable, CaseIterable, Identifiable {
    case round, square
    var id: String { rawValue }
    var title: String { self == .round ? "圆形" : "方形" }
    var symbol: String { self == .round ? "circle" : "square" }
}
struct InkColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    static let black = InkColor(red: 0, green: 0, blue: 0)
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    init(red: Double, green: Double, blue: Double) { self.red = red; self.green = green; self.blue = blue }
    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        red = rgb.redComponent; green = rgb.greenComponent; blue = rgb.blueComponent
    }
}
struct MarkPoint: Codable, Equatable {
    var x: Double
    var y: Double
    init(_ point: CGPoint) { x = point.x; y = point.y }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}
enum LassoEffect: String, Codable, CaseIterable, Identifiable {
    case mosaic, blur
    var id: String { rawValue }
    var title: String { self == .mosaic ? "马赛克" : "高斯模糊" }
}
struct MarkStroke: Codable, Equatable {
    var tool: MarkTool
    var diameter: Double
    var block: Double
    var points: [MarkPoint]
    var shape: BrushShape
    var color: InkColor
    var opacity: Double
    var blurRadius: Double
    var lassoEffect: LassoEffect
    var appliesBlur: Bool { tool == .blur || (tool == .lasso && lassoEffect == .blur) }
    init(tool: MarkTool, diameter: Double, block: Double, points: [MarkPoint], shape: BrushShape = .round, color: InkColor = .black, opacity: Double = 1, blurRadius: Double = 16, lassoEffect: LassoEffect = .mosaic) {
        self.tool = tool; self.diameter = diameter; self.block = block; self.points = points; self.shape = shape; self.color = color; self.opacity = opacity; self.blurRadius = blurRadius; self.lassoEffect = lassoEffect
    }
    enum CodingKeys: String, CodingKey { case tool, diameter, block, points, shape, color, opacity, blurRadius, lassoEffect }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tool = try values.decode(MarkTool.self, forKey: .tool)
        diameter = try values.decode(Double.self, forKey: .diameter)
        block = try values.decode(Double.self, forKey: .block)
        points = try values.decode([MarkPoint].self, forKey: .points)
        // Existing workspaces used round black strokes and have neither new field.
        shape = try values.decodeIfPresent(BrushShape.self, forKey: .shape) ?? .round
        color = try values.decodeIfPresent(InkColor.self, forKey: .color) ?? .black
        opacity = try values.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        blurRadius = try values.decodeIfPresent(Double.self, forKey: .blurRadius) ?? 16
        lassoEffect = try values.decodeIfPresent(LassoEffect.self, forKey: .lassoEffect) ?? .mosaic
    }
}
struct PhotoRecord: Codable, Identifiable {
    var id: UUID
    var name: String
    var storedName: String
    var width: Int
    var height: Int
    var strokes: [MarkStroke] = []
    var redo: [MarkStroke] = []
    var done = false
    var exported = false
}
struct WorkspaceArchive: Codable {
    var photos: [PhotoRecord]
    var selection: UUID?
}
enum ImageFailure: LocalizedError {
    case unreadable, tooLarge, render, encode
    var errorDescription: String? {
        switch self {
        case .unreadable: return "无法读取这张图片。请使用 PNG、JPEG、HEIC、WebP 等图片文件。"
        case .tooLarge: return "图片超过 6000 万像素，请先缩小后再导入。"
        case .render: return "无法创建图片画布，可能是可用内存不足。"
        case .encode: return "无法编码导出的 PNG 图片。"
        }
    }
}
enum ImageCodec {
    static func decode(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw ImageFailure.unreadable }
        guard Double(width) * Double(height) <= 60_000_000 else { throw ImageFailure.tooLarge }
        // ImageIO applies camera/HEIC orientation before editing and exporting.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                                      kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ImageFailure.unreadable }
        return image
    }
    static func png(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw ImageFailure.encode }
        // Fresh encoding deliberately excludes the source file's EXIF and other metadata.
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ImageFailure.encode }
    }
    static func thumbnail(_ image: CGImage) -> NSImage {
        let size = CGSize(width: 144, height: 112)
        let result = NSImage(size: size)
        result.lockFocus()
        let factor = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let rect = CGRect(x: (size.width - CGFloat(image.width)*factor)/2, y: (size.height - CGFloat(image.height)*factor)/2, width: CGFloat(image.width)*factor, height: CGFloat(image.height)*factor)
        NSImage(cgImage: image, size: .zero).draw(in: rect)
        result.unlockFocus()
        return result
    }
}
final class ImageRenderer {
    let original: CGImage
    private let context: CGContext
    private var pixelated: [Int: CGImage] = [:]
    private var blurredStrokeImage: CGImage?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    init(original: CGImage) throws {
        self.original = original
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: original.width, height: original.height, bitsPerComponent: 8, bytesPerRow: original.width*4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ImageFailure.render }
        self.context = context
        reset()
    }
    func reset() { restore(original) }
    func restore(_ image: CGImage) {
        blurredStrokeImage = nil
        context.clear(CGRect(x: 0, y: 0, width: original.width, height: original.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: original.width, height: original.height))
    }
    func render(_ strokes: [MarkStroke]) throws -> CGImage {
        reset()
        for stroke in strokes { try apply(stroke) }
        return try snapshot()
    }
    func snapshot() throws -> CGImage {
        guard let image = context.makeImage() else { throw ImageFailure.render }
        return image
    }
    func apply(_ stroke: MarkStroke, from: Int = 0) throws {
        guard !stroke.points.isEmpty else { return }
        if stroke.appliesBlur && (from == 0 || blurredStrokeImage == nil) {
            // Blur the composited image before this stroke, preserving earlier redactions.
            let input = CIImage(cgImage: try snapshot())
            let output = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: min(60, max(2, stroke.blurRadius))]).cropped(to: input.extent)
            guard let result = ciContext.createCGImage(output, from: input.extent) else { throw ImageFailure.render }
            blurredStrokeImage = result
        }
        let path = CGMutablePath()
        func converted(_ p: MarkPoint) -> CGPoint { CGPoint(x: p.x, y: Double(original.height) - p.y) }
        let start = max(0, from)
        if start >= stroke.points.count { return }
        let isLasso = stroke.tool == .lasso
        if stroke.tool == .line {
            guard stroke.points.count >= 2 else { return }
            path.move(to: converted(stroke.points[0]))
            path.addLine(to: converted(stroke.points[stroke.points.count-1]))
        } else if isLasso {
            guard stroke.points.count >= 3 else { return }
            path.move(to: converted(stroke.points[0]))
            for p in stroke.points.dropFirst() { path.addLine(to: converted(p)) }
            path.closeSubpath()
        } else if stroke.shape == .square {
            let r = stroke.diameter/2
            if stroke.points.count == 1 {
                let p = converted(stroke.points[0])
                path.addRect(CGRect(x: p.x-r, y: p.y-r, width: stroke.diameter, height: stroke.diameter))
            } else {
                for i in max(1,start)..<stroke.points.count {
                    addSquareSweep(from: converted(stroke.points[i-1]), to: converted(stroke.points[i]), radius: r, to: path)
                }
            }
        } else if stroke.points.count == 1 {
            let p = converted(stroke.points[0]), r = stroke.diameter/2
            path.addEllipse(in: CGRect(x: p.x-r, y: p.y-r, width: stroke.diameter, height: stroke.diameter))
        } else {
            path.move(to: converted(stroke.points[max(0,start-1)]))
            for i in max(1,start)..<stroke.points.count { path.addLine(to: converted(stroke.points[i])) }
        }
        context.saveGState()
        context.addPath(path)
        if stroke.tool == .line || (!isLasso && stroke.shape == .round && stroke.points.count > 1) {
            context.setLineWidth(stroke.diameter)
            context.setLineCap(stroke.tool == .line ? .butt : .round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
        }
        context.clip(using: isLasso ? .evenOdd : .winding)
        let bounds = CGRect(x: 0, y: 0, width: original.width, height: original.height)
        if stroke.tool == .solid || stroke.tool == .line {
            context.setAlpha(min(1, max(0, stroke.opacity)))
            context.setFillColor(stroke.color.cgColor)
            context.fill(bounds)
        } else if stroke.appliesBlur, let blurredStrokeImage {
            context.setBlendMode(.copy)
            context.draw(blurredStrokeImage, in: bounds)
        } else {
            let key = Int(stroke.block.rounded())
            let image: CGImage
            if let cached = pixelated[key] { image = cached }
            else {
                let input = CIImage(cgImage: original)
                let output = input.clampedToExtent().applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: key, kCIInputCenterKey: CIVector(x: 0, y: 0)]).cropped(to: input.extent)
                guard let rendered = ciContext.createCGImage(output, from: input.extent) else { context.restoreGState(); throw ImageFailure.render }
                if pixelated.count >= 3 { pixelated.removeAll() }
                pixelated[key] = rendered
                image = rendered
            }
            context.setBlendMode(.copy)
            context.draw(image, in: bounds)
        }
        context.restoreGState()
    }
    private func addSquareSweep(from a: CGPoint, to b: CGPoint, radius r: Double, to path: CGMutablePath) {
        // Convex hull of the endpoint squares gives a continuous, axis-aligned square brush.
        var corners: [CGPoint] = []
        for p in [a,b] {
            corners.append(CGPoint(x:p.x-r,y:p.y-r))
            corners.append(CGPoint(x:p.x+r,y:p.y-r))
            corners.append(CGPoint(x:p.x+r,y:p.y+r))
            corners.append(CGPoint(x:p.x-r,y:p.y+r))
        }
        corners.sort { left, right in left.x == right.x ? left.y < right.y : left.x < right.x }
        var unique: [CGPoint] = []
        for p in corners where unique.last != p { unique.append(p) }
        func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double { (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x) }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for p in unique {
            while lower.count >= 2 && cross(lower[lower.count-2],lower[lower.count-1],p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in unique.reversed() {
            while upper.count >= 2 && cross(upper[upper.count-2],upper[upper.count-1],p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        let hull = Array(lower.dropLast())+Array(upper.dropLast())
        if let first = hull.first { path.move(to:first); for p in hull.dropFirst() { path.addLine(to:p) }; path.closeSubpath() }
    }

}

// Store PNGs without recompressing, with explicit UTF-8 filenames for cross-platform ZIP readers.
enum ZipArchive {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >> 1) : crc >> 1 }
        return crc
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8) }
        return crc ^ 0xffffffff
    }
    private static func header(_ count: Int, values16: [Int: UInt16], values32: [Int: UInt32]) -> Data {
        var data = Data(repeating: 0, count: count)
        for (offset,value) in values16 { data[offset] = UInt8(value & 255); data[offset+1] = UInt8(value >> 8) }
        for (offset,value) in values32 { for i in 0..<4 { data[offset+i] = UInt8((value >> (i*8)) & 255) } }
        return data
    }
    static func write(folder: URL, to output: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard files.count < 65535 else { throw tooLarge() }
        FileManager.default.createFile(atPath:output.path,contents:nil)
        let handle = try FileHandle(forWritingTo:output)
        defer { try? handle.close() }
        var offset: UInt64 = 0, central = Data()
        let date: UInt16 = UInt16((2026-1980)<<9 | 1<<5 | 1)
        for file in files {
            try autoreleasepool {
                let bytes = try Data(contentsOf:file,options:.mappedIfSafe)
                let name = Data((folder.lastPathComponent+"/"+file.lastPathComponent).utf8)
                guard bytes.count <= Int(UInt32.max), name.count <= Int(UInt16.max), offset+UInt64(bytes.count)+UInt64(name.count)+30 < UInt64(UInt32.max) else { throw tooLarge() }
                let size = UInt32(bytes.count), crc = crc32(bytes)
                let local = header(30,values16:[4:20,6:0x800,12:date,26:UInt16(name.count)],values32:[0:0x04034b50,14:crc,18:size,22:size])
                try handle.write(contentsOf:local);try handle.write(contentsOf:name);try handle.write(contentsOf:bytes)
                central.append(header(46,values16:[4:20,6:20,8:0x800,14:date,28:UInt16(name.count)],values32:[0:0x02014b50,16:crc,20:size,24:size,42:UInt32(offset)]))
                central.append(name)
                offset += UInt64(30+name.count+bytes.count)
            }
        }
        guard offset+UInt64(central.count)<UInt64(UInt32.max) else { throw tooLarge() }
        try handle.write(contentsOf:central)
        try handle.write(contentsOf:header(22,values16:[8:UInt16(files.count),10:UInt16(files.count)],values32:[0:0x06054b50,12:UInt32(central.count),16:UInt32(offset)]))
    }
    private static func tooLarge() -> NSError {
        NSError(domain:"TuMa",code:3,userInfo:[NSLocalizedDescriptionKey:"ZIP 超过 4 GB 或文件数量过多，请使用“导出到文件夹”。"])
    }
}
