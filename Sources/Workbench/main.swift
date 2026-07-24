import AppKit
import SwiftUI

/// Workbench 的原生应用生命周期与主窗口管理器。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 强引用主窗口，支持关闭后从 Dock 重新打开。
    private var mainWindow: NSWindow?

    /// 应用启动完成后创建并展示唯一主窗口。
    /// - Parameter notification: AppKit 提供的启动完成通知。
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 外观交由 ThemeManager 管理（支持跟随系统 / 浅色 / 深色，并持久化用户选择）。
        let window = makeMainWindow()
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 用户点击 Dock 图标时重新显示已经关闭的主窗口。
    /// - Parameters:
    ///   - sender: 当前应用实例。
    ///   - flag: 当前是否仍有可见窗口。
    /// - Returns: 始终返回 true，表示已处理重新打开请求。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            mainWindow?.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    /// 创建并配置承载 SwiftUI 根视图的原生主窗口。
    /// - Returns: 已完成尺寸、标题栏与外观配置的窗口。
    private func makeMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Workbench"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 1040, height: 680)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)

        let frameName = NSWindow.FrameAutosaveName("Workbench.MainWindow")
        if !window.setFrameUsingName(frameName) {
            window.center()
        }
        _ = window.setFrameAutosaveName(frameName)

        window.contentViewController = NSHostingController(rootView: ContentView())

        // 绑定主题管理器：应用外观与窗口背景由当前主题模式驱动。
        ThemeManager.shared.attach(window)
        return window
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
