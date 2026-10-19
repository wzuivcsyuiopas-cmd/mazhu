// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import QuartzCore

struct PhotoSidebar: NSViewRepresentable {
    @ObservedObject var model: WorkspaceModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView(coordinator: context.coordinator)
    }
    static func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scroll = SidebarScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let collection = SidebarCollectionView()
        let layout = SidebarFlowLayout()
        layout.minimumLineSpacing = 4
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        collection.collectionViewLayout = layout
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.register(PhotoCardItem.self, forItemWithIdentifier: Coordinator.itemID)
        collection.dataSource = coordinator
        collection.delegate = coordinator
        collection.onRemove = { [weak model = coordinator.model] in model?.removeSelected() }
        scroll.documentView = collection
        coordinator.collection = collection
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.model = model
        context.coordinator.refresh()
        (scroll.documentView as? NSCollectionView)?.isSelectable = !model.busy
    }
    @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        static let itemID = NSUserInterfaceItemIdentifier("PhotoCard")
        var model: WorkspaceModel
        weak var collection: NSCollectionView?
        var ids: [UUID] = []
        var synchronizing = false
        init(_ model: WorkspaceModel) { self.model = model }
        func refresh() {
            guard let collection else { return }
            synchronizing = true
            let updated = model.photos.map(\.id)
            if ids != updated {
                ids = updated
                collection.reloadData()
            }
            let paths = Set(ids.enumerated().compactMap { model.selectedPhotoIDs.contains($0.element) ? IndexPath(item: $0.offset, section: 0) : nil })
            if collection.selectionIndexPaths != paths { collection.selectionIndexPaths = paths }
            for path in collection.indexPathsForVisibleItems() {
                if let item = collection.item(at: path) as? PhotoCardItem, model.photos.indices.contains(path.item) {
                    let photo = model.photos[path.item]
                    item.configure(photo, thumbnail: model.thumbnails[photo.id])
                }
            }
            synchronizing = false
        }
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { ids.count }
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: Self.itemID, for: indexPath) as! PhotoCardItem
            let photo = model.photos[indexPath.item]
            item.configure(photo, thumbnail: model.thumbnails[photo.id])
            return item
        }
        func collectionView(_ collectionView: NSCollectionView, layout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
            NSSize(width: max(1, (collectionView.enclosingScrollView?.contentSize.width ?? 222) - 20), height: 64)
        }
        func updateSelection(_ collection: NSCollectionView, preferred: Set<IndexPath> = []) {
            guard !synchronizing else { return }
            let selected = Set(collection.selectionIndexPaths.compactMap { ids.indices.contains($0.item) ? ids[$0.item] : nil })
            let focus = preferred.sorted().last.flatMap { ids.indices.contains($0.item) ? ids[$0.item] : nil }
            model.selectPhotos(selected, focus: focus)
        }
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { updateSelection(collectionView, preferred: indexPaths) }
        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { updateSelection(collectionView) }
        func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> { model.busy ? [] : indexPaths }
        func collectionView(_ collectionView: NSCollectionView, shouldDeselectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> { model.busy ? [] : indexPaths }

    }
}

final class SidebarScrollView: NSScrollView {
    private var viewportWidth: CGFloat = -1
    override var mouseDownCanMoveWindow: Bool { false }
    override func layout() {
        super.layout()
        guard let collection = documentView as? NSCollectionView else { return }
        // AppKit can resize the document before this callback. Compare the viewport
        // with its previous width, rather than with the already resized document.
        if abs(viewportWidth - contentSize.width) > 0.5 {
            viewportWidth = contentSize.width
            collection.setFrameSize(NSSize(width: contentSize.width, height: max(contentSize.height, collection.frame.height)))
            collection.collectionViewLayout?.invalidateLayout()
        }
    }
}

final class SidebarFlowLayout: NSCollectionViewFlowLayout {
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.width != collectionView?.bounds.width || super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }
}

final class SidebarCollectionView: NSCollectionView {
    override var mouseDownCanMoveWindow: Bool { false }
    var onRemove: (() -> Void)?
    private var insertionY: CGFloat? { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let y = insertionY {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect:NSRect(x:10,y:y-1.5,width:max(1,bounds.width-20),height:3),xRadius:1.5,yRadius:1.5).fill()
        }
    }
    override func mouseDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let start = convert(event.locationInWindow, from: nil)
        guard isSelectable, modifiers.isEmpty, let path = indexPathForItem(at: start),
              let coordinator = delegate as? PhotoSidebar.Coordinator, let window else {
            super.mouseDown(with: event); return
        }
        window.makeFirstResponder(self)
        let alreadySelected = selectionIndexPaths.contains(path)
        if !alreadySelected {
            selectionIndexPaths = [path]
            coordinator.updateSelection(self, preferred: [path])
        }
        let moving = coordinator.model.selectedPhotoIDs
        var destination: Int?
        defer { insertionY = nil }
        // Keep queue reordering local. Background drags still use AppKit's native marquee.
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) {
            if next.type == .keyDown { if next.keyCode == 53 { return }; continue }
            if next.type == .leftMouseUp {
                if let destination {
                    coordinator.model.movePhotos(moving, before: destination)
                    coordinator.refresh()
                } else if alreadySelected && selectionIndexPaths.count > 1 {
                    selectionIndexPaths = [path]
                    coordinator.updateSelection(self, preferred: [path])
                }
                return
            }
            let point = convert(next.locationInWindow, from: nil)
            guard destination != nil || hypot(point.x-start.x, point.y-start.y) >= 4 else { continue }
            _ = autoscroll(with: next)
            var target = coordinator.ids.count
            var marker: CGFloat = 8
            for index in coordinator.ids.indices {
                guard let attributes = layoutAttributesForItem(at:IndexPath(item:index,section:0)) else { continue }
                if point.y < attributes.frame.midY {
                    target = index; marker = attributes.frame.minY-2; break
                }
                marker = attributes.frame.maxY+2
            }
            destination = target
            insertionY = marker
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard isSelectable else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        if let path = indexPathForItem(at: point), !selectionIndexPaths.contains(path) {
            selectionIndexPaths = [path]
            (delegate as? PhotoSidebar.Coordinator)?.updateSelection(self, preferred: [path])
        }
        guard !selectionIndexPaths.isEmpty else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: selectionIndexPaths.count > 1 ? "从队列移除所选的 \(selectionIndexPaths.count) 张图片" : "从队列移除", action: #selector(removeSelection(_:)), keyEquivalent: "")
        item.target = self; menu.addItem(item)
        return menu
    }
    @objc func removeSelection(_ sender: Any?) { onRemove?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { if isSelectable { onRemove?() }; return }
        super.keyDown(with: event)
    }
}

private struct PhotoCard: View {
    let photo: PhotoRecord?
    let thumbnail: NSImage?
    var body: some View {
        Group {
            if let photo { PhotoRow(photo: photo, thumbnail: thumbnail).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
final class PhotoCardItem: NSCollectionViewItem {
    private var photo: PhotoRecord?
    private var thumbnail: NSImage?
    private var hosting: PassiveCardView?
    override func loadView() {
        view = PhotoCardRootView()
        let host = PassiveCardView(rootView: PhotoCard(photo: nil, thumbnail: nil))
        host.sizingOptions = []
        host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        host.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.topAnchor.constraint(equalTo: view.topAnchor), host.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting = host
        refreshSelection()
    }
    override var isSelected: Bool { didSet { refreshSelection() } }
    override var highlightState: NSCollectionViewItem.HighlightState { didSet { refreshSelection() } }
    private func refreshSelection() {
        guard isViewLoaded, let root = view as? PhotoCardRootView else { return }
        switch highlightState {
        case .forSelection: root.showsSelection = true
        case .forDeselection: root.showsSelection = false
        default: root.showsSelection = isSelected
        }
    }
    func configure(_ photo: PhotoRecord, thumbnail: NSImage?) {
        self.photo = photo; self.thumbnail = thumbnail
        refresh()
    }
    private func refresh() {
        guard isViewLoaded else { return }
        hosting?.rootView = PhotoCard(photo: photo, thumbnail: thumbnail)
    }
}
private final class PassiveCardView: NSHostingView<PhotoCard> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PhotoCardRootView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    var showsSelection = false { didSet { updateSelectionColor() } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 9
        updateSelectionColor()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSelectionColor()
    }
    private func updateSelectionColor() {
        // Native layer updates remain visible inside AppKit's marquee tracking loop.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.backgroundColor = showsSelection ? NSColor.labelColor.withAlphaComponent(0.10).cgColor : NSColor.clear.cgColor
            CATransaction.commit()
        }
    }
}
