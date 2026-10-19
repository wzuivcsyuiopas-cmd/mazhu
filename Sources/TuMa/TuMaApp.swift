// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

@main
struct TuMaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: WorkspaceModel
    init() {
        let qaRoot = ProcessInfo.processInfo.environment["TUMA_TEST_WORKSPACE"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let workspace = WorkspaceModel(root: qaRoot)
        _model = StateObject(wrappedValue: workspace)
        AppDelegate.workspace = workspace
    }
    var body: some Scene {
        Window("码住", id: "workspace") {
            WorkspaceView(model: model)
                .background(WindowBehavior().frame(width:0,height:0))
                .background(WindowMetrics().frame(width:0,height:0))
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1220, height: 800)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入图片…", systemImage: "plus", action: model.importPanel).keyboardShortcut("o").disabled(model.busy)
                Button("导出已完成的图片…", systemImage: "square.and.arrow.up") { model.exportPanel(zip: true) }
                    .keyboardShortcut("e", modifiers: [.command,.shift]).disabled(model.completed == 0 || model.busy)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销打码", action: model.undo).keyboardShortcut("z").disabled(!model.canUndo)
                Button("重做打码", action: model.redo).keyboardShortcut("z", modifiers: [.command,.shift]).disabled(!model.canRedo)
            }
            CommandMenu("图片") {
                Button("上一张") { model.navigate(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("下一张") { model.navigate(1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Divider()
                Button("完成并下一张", action: model.markDone).keyboardShortcut(.return, modifiers: []).disabled(model.selected == nil || model.busy || model.image == nil)
                Button("适应窗口") { model.zoom = 0 }.keyboardShortcut("0")
                Button("实际大小") { model.zoom = 1 }.keyboardShortcut("1")
                Divider()
                Button("滚轮快捷操作…") {
                    let alert = NSAlert()
                    alert.messageText = "画布滚轮快捷操作"
                    alert.informativeText = "⌘＋滚轮：以鼠标位置为中心缩放\n⌥＋滚轮：笔刷／直线粗细；圈选颗粒或模糊强度\n⌥⇧＋滚轮：马赛克／圈选颗粒；画笔／直线不透明度；模糊强度\n\n普通滚轮：平移画布\n触控板：双指平移、捏合缩放\n⌘0：适应窗口；⌘1：实际大小\n\n向上滚动增大，向下滚动减小；触控板方向遵循系统滚动设置。"
                    alert.addButton(withTitle: "好")
                    alert.runModal()
                }
            }
        }
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var workspace: WorkspaceModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.workspace else { return .terminateNow }
        if model.busy {
            let alert = NSAlert(); alert.messageText = "正在处理图片"; alert.informativeText = "请等待当前导入或导出完成后再退出。"; alert.addButton(withTitle: "好"); alert.runModal()
            return .terminateCancel
        }
        model.finishDrawing?(); model.saveNow()
        return .terminateNow
    }
    func application(_ application: NSApplication, open urls: [URL]) { Self.workspace?.importURLs(urls) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil) }
        return true
    }
}
