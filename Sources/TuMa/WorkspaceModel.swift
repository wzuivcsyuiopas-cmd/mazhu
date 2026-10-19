// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImportedPhoto {
    var record: PhotoRecord
    var thumbnail: NSImage
}
@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var photos: [PhotoRecord] = []
    @Published var selectedPhotoIDs = Set<UUID>()
    private var updatingMultipleSelection = false
    @Published var selection: UUID? {
        didSet {
            if !updatingMultipleSelection { selectedPhotoIDs = Set(selection.map { [$0] } ?? []) }
            if selection != oldValue { loadSelection() }
        }
    }
    @Published var image: CGImage?
    @Published var thumbnails: [UUID: NSImage] = [:]
    @Published var revision = 0
    @Published var tool: MarkTool = .mosaic
    @Published var brushShape: BrushShape = .round
    @Published var brushColor: Color = .black
    @Published var inkOpacity = 1.0
    @Published var brushSize = 48.0
    @Published var blockSize = 24.0
    @Published var blurRadius = 16.0
    @Published var lassoEffect: LassoEffect = .mosaic
    @Published var zoom = 0.0
    @Published var busy = false
    @Published var progress = ""
    @Published var message: String?
    @Published var errorMessage: String?
    var finishDrawing: (() -> Void)?
    private var hoveredControls = Set<UUID>()
    var pointerOverControls: Bool { !hoveredControls.isEmpty }
    var controlHoverChanged: (() -> Void)?
    func setControlHover(_ id: UUID, inside: Bool) {
        if inside { hoveredControls.insert(id) } else { hoveredControls.remove(id) }
        controlHoverChanged?()
        if pointerOverControls { NSCursor.arrow.set() }
    }
    let root: URL
    private var saveWork: DispatchWorkItem?
    private var restoreSelection = false
    private var loadID = UUID()
    private let fm = FileManager.default
    var selected: PhotoRecord? { photos.first { $0.id == selection } }
    var selectedIndex: Int? { photos.firstIndex { $0.id == selection } }
    var completed: Int { photos.filter(\.done).count }
    var canUndo: Bool { !(selected?.strokes.isEmpty ?? true) && !busy }
    var canRedo: Bool { !(selected?.redo.isEmpty ?? true) && !busy }
    var originals: URL { root.appendingPathComponent("Originals", isDirectory: true) }
    var sessionURL: URL { root.appendingPathComponent("workspace.json") }

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TuMa", isDirectory: true)
        do {
            try fm.createDirectory(at: originals, withIntermediateDirectories: true)
            if fm.fileExists(atPath: sessionURL.path) {
                let archive = try JSONDecoder().decode(WorkspaceArchive.self, from: Data(contentsOf: sessionURL))
                photos = archive.photos.filter { fm.fileExists(atPath: originals.appendingPathComponent($0.storedName).path) }
                selection = photos.contains { $0.id == archive.selection } ? archive.selection : photos.first?.id
            }
        } catch { errorMessage = "工作区读取失败：\(error.localizedDescription)。现有文件已保留。" }
        // Property observers do not run during initialization.
        selectedPhotoIDs = Set(selection.map { [$0] } ?? [])
        if selection != nil { loadSelection() }
        loadThumbnails()
    }
    func saveNow() {
        saveWork?.cancel()
        do {
            let data = try JSONEncoder().encode(WorkspaceArchive(photos: photos, selection: selection))
            try data.write(to: sessionURL, options: .atomic)
        } catch { errorMessage = "工作区保存失败：\(error.localizedDescription)" }
    }
    func saveSoon() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now()+0.35, execute: work)
    }
    func loadSelection() {
        let token = UUID(); loadID = token
        image = nil
        guard let record = selected else { return }
        let url = originals.appendingPathComponent(record.storedName)
        Task {
            do {
                let decoded = try await Task.detached(priority: .userInitiated) { try ImageCodec.decode(url) }.value
                guard token == loadID else { return }
                image = decoded
                saveSoon()
            } catch { if token == loadID { errorMessage = error.localizedDescription } }
        }
    }
    private func loadThumbnails() {
        let records = photos, folder = originals
        Task {
            for record in records {
                if thumbnails[record.id] != nil { continue }
                let thumb: NSImage? = await Task.detached(priority: .utility) {
                    guard let original = try? ImageCodec.decode(folder.appendingPathComponent(record.storedName)),
                          let renderer = try? ImageRenderer(original: original),
                          let result = try? renderer.render(record.strokes) else { return nil }
                    return ImageCodec.thumbnail(result)
                }.value
                if let thumb { thumbnails[record.id] = thumb }
            }
        }
    }
    private func present(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else { panel.begin(completionHandler: completion) }
    }
    func importPanel() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "导入需要打码的图片"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "导入"
        present(panel) { [weak self] response in
            if response == .OK { Task { @MainActor in self?.importURLs(panel.urls) } }
        }
    }
    func importURLs(_ urls: [URL]) {
        guard !busy else { notify("正在处理图片，请稍后再导入"); return }
        finishDrawing?()
        busy = true; progress = "正在导入图片…"
        let folder = originals
        Task {
            var imported: [ImportedPhoto] = [], failures: [String] = []
            for (offset, url) in urls.enumerated() {
                progress = "正在导入 \(offset+1) / \(urls.count)…"
                do {
                    let result = try await Task.detached(priority: .userInitiated) { () throws -> ImportedPhoto in
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let image = try ImageCodec.decode(url)
                        let id = UUID(), stored = id.uuidString + "." + (url.pathExtension.isEmpty ? "image" : url.pathExtension)
                        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(stored))
                        return ImportedPhoto(record: PhotoRecord(id: id, name: url.lastPathComponent, storedName: stored, width: image.width, height: image.height), thumbnail: ImageCodec.thumbnail(image))
                    }.value
                    imported.append(result)
                } catch { failures.append(url.lastPathComponent + "：" + error.localizedDescription) }
            }
            for entry in imported { photos.append(entry.record); thumbnails[entry.record.id] = entry.thumbnail }
            if let first = imported.first { selection = first.record.id }
            busy = false; saveNow()
            notify("已导入 \(imported.count) 张图片")
            if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        }
    }
    func paste(from board: NSPasteboard = .general) {
        guard !busy else { notify("正在处理图片，请稍后再粘贴"); return }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            importURLs(urls); return
        }
        let data = board.data(forType: .png) ?? board.data(forType: .tiff)
        guard let data else { notify("剪贴板里没有图片。复制图片或 Finder 中的图片文件后再粘贴。"); return }
        do {
            let ext = board.data(forType: .png) != nil ? "png" : "tiff"
            let temp = fm.temporaryDirectory.appendingPathComponent("TuMa-paste-"+UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            let date = DateFormatter(); date.dateFormat = "yyyyMMdd-HHmmss"
            let file = temp.appendingPathComponent("粘贴图片-"+date.string(from: Date())+"."+ext)
            try data.write(to: file, options: .atomic)
            importURLs([file])
            Task {
                while busy { try? await Task.sleep(for: .milliseconds(100)) }
                try? fm.removeItem(at: temp)
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func commit(_ stroke: MarkStroke, rendered: CGImage) {
        guard let i = selectedIndex else { return }
        photos[i].strokes.append(stroke)
        photos[i].redo = []; photos[i].done = false; photos[i].exported = false
        thumbnails[photos[i].id] = ImageCodec.thumbnail(rendered)
        revision += 1; saveSoon()
    }
    func undo() {
        finishDrawing?()
        guard !busy, let i = selectedIndex, let last = photos[i].strokes.popLast() else { return }
        photos[i].redo.append(last); photos[i].done = false; photos[i].exported = false
        revision += 1; saveSoon()
    }
    func redo() {
        finishDrawing?()
        guard !busy, let i = selectedIndex, let last = photos[i].redo.popLast() else { return }
        photos[i].strokes.append(last); photos[i].done = false; photos[i].exported = false
        revision += 1; saveSoon()
    }
    func reset() {
        finishDrawing?()
        guard !busy, let i = selectedIndex, !photos[i].strokes.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "重置这张图片？"; alert.informativeText = "本张图片的打码将被清除。原始文件不会被修改。"
        alert.addButton(withTitle: "重置"); alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            photos[i].strokes = []; photos[i].redo = []; photos[i].done = false; photos[i].exported = false
            revision += 1; saveSoon()
        }
    }
    func navigate(_ delta: Int) {
        finishDrawing?()
        guard !busy, let i = selectedIndex, photos.indices.contains(i+delta) else { return }
        selection = photos[i+delta].id
    }
    func markDone() {
        finishDrawing?()
        guard !busy, let i = selectedIndex else { return }
        photos[i].done = true; saveNow()
        if photos.indices.contains(i+1) { selection = photos[i+1].id }
        else { notify("已确认完成，可以批量导出") }
    }
    func selectPhotos(_ ids: Set<UUID>, focus: UUID? = nil) {
        guard !busy else { return }
        let valid = ids.intersection(Set(photos.map(\.id)))
        let next = focus.flatMap { valid.contains($0) ? $0 : nil }
            ?? selection.flatMap { valid.contains($0) ? $0 : nil }
            ?? photos.first(where: { valid.contains($0.id) })?.id
        if let next, next != selection { finishDrawing?() }
        selectedPhotoIDs = valid
        updatingMultipleSelection = true
        // An empty sidebar selection leaves the current canvas available for editing.
        if let next { selection = next }
        updatingMultipleSelection = false
    }
    func movePhotos(_ ids: Set<UUID>, before destination: Int) {
        guard !busy, !ids.isEmpty else { return }
        finishDrawing?()
        let boundary = min(max(0, destination), photos.count)
        let moving = photos.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        let insertion = boundary - photos.prefix(boundary).filter { ids.contains($0.id) }.count
        var reordered = photos.filter { !ids.contains($0.id) }
        reordered.insert(contentsOf: moving, at: insertion)
        photos = reordered
        saveNow()
    }
    func removeSelected() {
        finishDrawing?()
        guard !busy, !selectedPhotoIDs.isEmpty else { return }
        let removed = selectedPhotoIDs
        let position = photos.firstIndex { removed.contains($0.id) } ?? 0
        photos.removeAll { removed.contains($0.id) }
        for id in removed { thumbnails.removeValue(forKey: id) }
        if let current = selection, !removed.contains(current) {
            selectedPhotoIDs = [current]
        } else {
            selection = photos.isEmpty ? nil : photos[min(position, photos.count-1)].id
        }
        saveNow()
        // Workspace copies are retained for recovery; user source files are never deleted.
    }
    func notify(_ text: String) {
        message = text
        Task { try? await Task.sleep(for: .seconds(4)); if message == text { message = nil } }
    }
    func exportPanel(zip: Bool) {
        finishDrawing?()
        guard !busy, completed > 0 else { return }
        if zip {
            let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]
            panel.title = "导出已完成的图片"; panel.nameFieldStringValue = "码住图片.zip"
            present(panel) { [weak self] response in
                if response == .OK, let url = panel.url { Task { @MainActor in self?.export(to: url, zip: true) } }
            }
        } else {
            let panel = NSOpenPanel(); panel.title = "选择批量导出的目标文件夹"
            panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.prompt = "导出到这里"
            present(panel) { [weak self] response in
                if response == .OK, let url = panel.url { Task { @MainActor in self?.export(to: url, zip: false) } }
            }
        }
    }
    func export(to destination: URL, zip: Bool) {
        guard !busy else { return }
        let ready = photos.filter(\.done)
        guard !ready.isEmpty else { return }
        busy = true; progress = "正在准备导出…"
        let folder = originals
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { () async throws -> URL in
                    let fm = FileManager.default
                    let temp = fm.temporaryDirectory.appendingPathComponent("TuMa-export-"+UUID().uuidString, isDirectory: true)
                    let images = temp.appendingPathComponent("码住图片", isDirectory: true)
                    try fm.createDirectory(at: images, withIntermediateDirectories: true)
                    defer { try? fm.removeItem(at: temp) }
                    for (i, record) in ready.enumerated() {
                        try autoreleasepool {
                            let original = try ImageCodec.decode(folder.appendingPathComponent(record.storedName))
                            let rendered = try ImageRenderer(original: original).render(record.strokes)
                            let stem = (record.name as NSString).deletingPathExtension
                            let safe = String(stem.map { "/:\\".contains($0) ? "_" : $0 }.prefix(100))
                            let name = String(format: "%03d_", i+1)+safe+"_已打码.png"
                            try ImageCodec.png(rendered, to: images.appendingPathComponent(name))
                        }
                        await MainActor.run { self.progress = "正在导出 \(i+1) / \(ready.count)…" }
                    }
                    let access = destination.startAccessingSecurityScopedResource()
                    defer { if access { destination.stopAccessingSecurityScopedResource() } }
                    if zip {
                        let archive = temp.appendingPathComponent("export.zip")
                        try ZipArchive.write(folder: images, to: archive)
                        let staging = destination.deletingLastPathComponent().appendingPathComponent(".tuma-"+UUID().uuidString+".zip")
                        try fm.copyItem(at: archive, to: staging)
                        defer { try? fm.removeItem(at: staging) }
                        if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: staging) }
                        else { try fm.moveItem(at: staging, to: destination) }
                        return destination
                    } else {
                        let date = DateFormatter(); date.dateFormat = "yyyyMMdd-HHmmss"
                        var target = destination.appendingPathComponent("码住图片-"+date.string(from: Date()), isDirectory: true)
                        if fm.fileExists(atPath: target.path) { target = destination.appendingPathComponent("码住图片-"+UUID().uuidString.prefix(8), isDirectory: true) }
                        try fm.copyItem(at: images, to: target)
                        return target
                    }
                }.value
                for i in photos.indices where ready.contains(where: { $0.id == photos[i].id }) { photos[i].exported = true }
                saveNow(); notify("已导出 \(ready.count) 张原分辨率 PNG 图片")
                NSWorkspace.shared.activateFileViewerSelecting([result])
            } catch { errorMessage = "导出失败：\(error.localizedDescription)" }
            busy = false
        }

    }
}
