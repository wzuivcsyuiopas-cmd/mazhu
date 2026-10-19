// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceModel
    @State private var targeted = false
    @State private var showingColors = false
    @State private var optionsWidth: CGFloat = 475
    @State private var detailWidth: CGFloat = 900
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationSplitView {
            PhotoSidebar(model: model)
            .navigationSplitViewColumnWidth(min: 190, ideal: 222, max: 300)
        } detail: {
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                    .ignoresSafeArea(.container, edges: .top)
                    .allowsHitTesting(false)
                if model.selected != nil {
                    NativeCanvas(model: model)
                        .ignoresSafeArea(.container, edges: .top)
                        .accessibilityLabel("图片打码画布")
                    if model.image == nil && !model.busy { ProgressView("正在读取图片…") }
                } else { emptyState }
                if targeted {
                    RoundedRectangle(cornerRadius: 16).fill(.tint.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [8])))
                        .padding(14).allowsHitTesting(false)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
            .overlay(alignment: .bottomLeading) {
                if model.selected != nil { brushBar.padding(18) }
            }
            .overlay(alignment: .bottomTrailing) {
                if model.selected != nil {
                    pageControls.padding(.trailing, 18).padding(.bottom, detailWidth < 830 ? 78 : 18)
                }
            }
            .overlay {
                if model.busy {
                    ZStack {
                        Color(nsColor: .windowBackgroundColor).opacity(0.65)
                        VStack(spacing: 14) { ProgressView(); Text(model.progress).font(.callout) }
                            .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .toolbar { toolbar }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .scrollEdgeEffectHidden(true, for: .top)
            .overlay(alignment: .top) {
                if let text = model.message {
                    Label(text, systemImage: "checkmark.circle.fill")
                        .font(.callout).padding(.horizontal, 18).padding(.vertical, 11)
                        .glassEffect(.regular, in: .capsule).padding(.top, 14).allowsHitTesting(false)
                }
            }
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onPasteCommand(of: [.image, .fileURL]) { _ in model.paste() }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
            guard !model.busy else { return false }
            Task {
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                            continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
                        }
                    }
                    if let url { urls.append(url) }
                }
                if !urls.isEmpty { model.importURLs(urls) }
            }
            return true
        }
        .alert("无法完成操作", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .frame(minWidth: 920, minHeight: 520)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("导入图片，直接涂抹", systemImage: "photo.badge.plus")
        } description: {
            Text("把图片拖到这里，或按 ⌘V 粘贴。")
        } actions: {
            Button("导入图片…", systemImage: "plus", action: model.importPanel)
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
    private var brushBar: some View {
        brushOptions
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) { optionsWidth = width + 36 }
            }
            // Replace only the controls; the outer frame and glass keep their identity.
            .id(model.tool.rawValue + (model.tool == .lasso ? model.lassoEffect.rawValue : ""))
            .transition(.blurReplace)
            .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: model.tool)
            .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: model.lassoEffect)
            .padding(.leading, 18)
            .frame(width: optionsWidth, height: 48, alignment: .leading)
            .glassEffect(.regular.interactive(), in: .capsule)
            .fixedSize()
            .onChange(of: model.tool) { showingColors = false }
            .modifier(ControlPointer(model: model))
            .disabled(model.busy)
    }
    private var brushOptions: some View {
        HStack(spacing: 12) {
            if model.tool == .lasso {
                Picker("圈选效果", selection: $model.lassoEffect) {
                    ForEach(LassoEffect.allCases) { effect in Text(effect.title).tag(effect) }
                }.labelsHidden().pickerStyle(.menu).fixedSize().accessibilityLabel("圈选效果")
                Divider().frame(height: 18)
            }
            if model.tool == .mosaic || model.tool == .solid || model.tool == .blur {
                Menu {
                    ForEach(BrushShape.allCases) { shape in
                        Button { model.brushShape = shape } label: { Label(shape.title, systemImage: shape.symbol) }
                    }
                } label: { Label(model.brushShape.title, systemImage: model.brushShape.symbol) }
                    .menuStyle(.borderlessButton).fixedSize().help("笔刷形状")
                Divider().frame(height: 18)
            }
            if model.tool != .lasso {
                Text(model.tool == .line ? "粗细" : "笔刷").font(.callout).fixedSize()
                Slider(value: wholeNumber($model.brushSize), in: 8...180)
                    .frame(width: 95).accessibilityLabel(model.tool == .line ? "直线粗细" : "笔刷大小")
                Text("\(Int(model.brushSize))").font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 25)
            }
            if model.tool == .solid || model.tool == .line {
                Divider().frame(height: 18)
                colorButton
                Divider().frame(height: 18)
                Text("不透明度").font(.callout).fixedSize()
                Slider(value: $model.inkOpacity, in: 0...1).frame(width: 78).accessibilityLabel("不透明度")
                Text("\(Int((model.inkOpacity*100).rounded()))%")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 36)
            } else if model.tool == .blur || (model.tool == .lasso && model.lassoEffect == .blur) {
                if model.tool == .blur { Divider().frame(height: 18) }
                Text("强度").font(.callout).fixedSize()
                Slider(value: wholeNumber($model.blurRadius), in: 2...60)
                    .frame(width: 95).accessibilityLabel("高斯模糊强度")
                Text("\(Int(model.blurRadius))").font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 25)
            } else {
                if model.tool == .mosaic { Divider().frame(height: 18) }
                Text("颗粒").font(.callout).fixedSize()
                Slider(value: wholeNumber($model.blockSize), in: 6...100)
                    .frame(width: model.tool == .lasso ? 120 : 85).accessibilityLabel("马赛克颗粒大小")
                Text("\(Int(model.blockSize))").font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 25)
            }
        }
        .fixedSize(horizontal: true, vertical: false)

    }
    private func wholeNumber(_ value: Binding<Double>) -> Binding<Double> {
        Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0.rounded() })
    }
    private var colorButton: some View {
        Button { showingColors.toggle() } label: {
            RoundedRectangle(cornerRadius: 5).fill(model.brushColor)
                .frame(width: 24, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain).accessibilityLabel(model.tool == .line ? "直线颜色" : "笔刷颜色").help(model.tool == .line ? "直线颜色" : "画笔颜色")
        .popover(isPresented: $showingColors) {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.tool == .line ? "直线颜色" : "画笔颜色").font(.headline)
                HStack(spacing: 9) {
                    ForEach(BrushColorOption.allCases) { option in
                        Button { model.brushColor = option.color; showingColors = false } label: {
                            Circle().fill(option.color).frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(.secondary.opacity(0.4)))
                        }.buttonStyle(.plain).accessibilityLabel(option.title).help(option.title)
                    }
                }
                ColorPicker("自定颜色", selection: $model.brushColor, supportsOpacity: false)
            }.padding(18)
        }
    }
    private var pageControls: some View {
        HStack(spacing: 10) {
            Button { model.navigate(-1) } label: { Image(systemName: "chevron.left") }
                .help("上一张（←）").disabled((model.selectedIndex ?? 0) == 0 || model.busy)
            Text("\((model.selectedIndex ?? 0)+1) / \(model.photos.count)")
                .monospacedDigit().foregroundStyle(.secondary).fixedSize()
            Button { model.navigate(1) } label: { Image(systemName: "chevron.right") }
                .help("下一张（→）").disabled((model.selectedIndex ?? 0) >= model.photos.count-1 || model.busy)
            Divider().frame(height: 20)
            Button("完成下一张", systemImage: "checkmark") { model.markDone() }
                .fontWeight(.medium).disabled(model.busy || model.image == nil)
                .help("确认本张完成并进入下一张（回车）")
        }
        .buttonStyle(.plain).font(.callout)
        .padding(.horizontal, 15).padding(.vertical, 14)
        .glassEffect(.regular, in: .capsule)
        .fixedSize()
        .modifier(ControlPointer(model: model))
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("撤销", systemImage: "arrow.uturn.backward", action: model.undo).disabled(!model.canUndo).help("撤销（⌘Z）")
            Button("重做", systemImage: "arrow.uturn.forward", action: model.redo).disabled(!model.canRedo).help("重做（⇧⌘Z）")
        }
        ToolbarItem(placement: .navigation) {
            Menu {
                Button("适应窗口") { model.zoom = 0 }
                Divider()
                ForEach([0.25,0.5,1.0,2.0,4.0], id: \.self) { zoom in
                    Button("\(Int(zoom*100))%") { model.zoom = zoom }
                }
            } label: { Label("缩放", systemImage: "plus.magnifyingglass") }
                .help("缩放图片").disabled(model.selected == nil)
        }
        ToolbarItem(placement: .navigation) {
            Menu {
                Button("重置本张打码…", systemImage: "arrow.counterclockwise", action: model.reset)
                    .disabled(model.selected?.strokes.isEmpty ?? true)
                Button(model.selectedPhotoIDs.count > 1 ? "从队列移除所选图片" : "从队列移除", systemImage: "minus.circle", action: model.removeSelected)
                    .disabled(model.selectedPhotoIDs.isEmpty)
            } label: { Label("更多", systemImage: "ellipsis") }.disabled(model.busy)
        }
        ToolbarSpacer(.flexible, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            ToolPicker(selection: $model.tool, isEnabled: !model.busy)
                .frame(width: ToolPicker.width, height: ToolPicker.height)
                .modifier(ControlPointer(model: model))
        }.sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 12) {
                Button("导入图片", systemImage: "plus", action: model.importPanel)
                    .frame(width: 24, height: 24).help("导入图片（⌘O）").disabled(model.busy)
                Menu {
                    Button("导出 ZIP 压缩包…", systemImage: "doc.zipper") { model.exportPanel(zip: true) }
                    Button("导出到文件夹…", systemImage: "folder") { model.exportPanel(zip: false) }
                } label: { Label("导出", systemImage: "square.and.arrow.up") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24, height: 24)
                    .disabled(model.completed == 0 || model.busy).help("批量导出已完成的图片")
            }
            .labelStyle(.iconOnly).buttonStyle(.plain).font(.system(size: 17))
            .padding(.horizontal, 13).padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: .capsule)
            .modifier(ControlPointer(model: model))
        }.sharedBackgroundVisibility(.hidden)
    }

}

private enum BrushColorOption: String, CaseIterable, Identifiable {
    case black, white, red, orange, yellow, green, blue, purple
    var id: String { rawValue }
    var title: String {
        switch self { case .black: return "黑色"; case .white: return "白色"; case .red: return "红色"; case .orange: return "橙色"; case .yellow: return "黄色"; case .green: return "绿色"; case .blue: return "蓝色"; case .purple: return "紫色" }
    }
    var color: Color {
        switch self { case .black: return .black; case .white: return .white; case .red: return .red; case .orange: return .orange; case .yellow: return .yellow; case .green: return .green; case .blue: return .blue; case .purple: return .purple }
    }
}

private struct ControlPointer: ViewModifier {
    let model: WorkspaceModel
    @State private var hoverID = UUID()
    func body(content: Content) -> some View {
        content
            .contentShape(.capsule)
            .onHover { inside in model.setControlHover(hoverID, inside: inside) }
            .onDisappear { model.setControlHover(hoverID, inside: false) }
    }
}
