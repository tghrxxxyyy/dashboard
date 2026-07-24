import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 菜单栏状态项控制器：在系统状态栏常驻 Workbench 图标，点击弹出资源概览。
@MainActor
final class StatusBarController: NSObject {
    /// 系统状态栏的常驻条目。
    private let statusItem: NSStatusItem
    /// 概览面板使用的数据源。
    private let monitor = SystemMonitor()
    /// 主窗口引用，用于从概览跳转回完整界面。
    private weak var mainWindow: NSWindow?
    /// 自定义弹出面板：使用 NSPanel 替代 NSPopover，拿到完整的窗口定位/尺寸控制权，
    /// 彻底摆脱 NSPopover 锚定到状态项底边时把内容顶到菜单栏后面的问题。
    private var overviewPanel: NSPanel?
    /// 监听面板外的鼠标点击用于自动关闭。
    private var outsideClickMonitor: Any?
    /// 鼠标离开 popover 后到真正关闭的宽容期，方便用户短暂移出再回来。
    private static let closeGrace: TimeInterval = 0.15
    /// 计划中的延迟关闭任务，便于鼠标重新进入时取消。
    private var pendingCloseTask: DispatchWorkItem?

    /// 创建状态项并绑定弹出行为。
    /// - Parameter mainWindow: 主窗口引用，用于概览中跳转到完整界面。
    init(mainWindow: NSWindow?) {
        self.mainWindow = mainWindow
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let symbol = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Workbench 概览")?
                .withSymbolConfiguration(config)
            symbol?.isTemplate = true
            button.image = symbol
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    /// 切换概览面板的显示与隐藏，并在关闭时停止采样以节省资源。
    @objc private func togglePopover() {
        if overviewPanel != nil {
            closePopover()
            return
        }
        monitor.start()
        // 关键：用点击瞬间的鼠标屏幕坐标作为锚点，不依赖 button.window（在 macOS 27 上菜单栏是独立进程窗口，转换不可靠）。
        let clickScreenPoint = NSEvent.mouseLocation
        showOverviewPanel(at: clickScreenPoint)
    }

    /// 创建并显示概览面板：先让 SwiftUI 完成布局拿到真实尺寸，再把面板顶边精准对齐菜单栏下方 4pt。
    /// - Parameter screenPoint: 状态项被点击时的鼠标屏幕坐标（用于水平居中）。
    private func showOverviewPanel(at screenPoint: NSPoint) {
        // 构建 SwiftUI 内容
        let contentView = StatusBarOverview(monitor: monitor, openMain: { [weak self] in
            self?.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self?.closePopover()
        })
        let hosting = NSHostingController(rootView: contentView)
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = .intrinsicContentSize
        }

        // 用无边框浮动面板取代 NSPopover，避开 NSPopover 把内容顶到菜单栏后面的问题
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false

        // 强制布局 SwiftUI 内容，拿到真实高度（不调用的话 fittingSize 拿到的会是占位尺寸）
        hosting.view.layoutSubtreeIfNeeded()
        let fittingSize = hosting.view.fittingSize

        // 用屏幕真实可见区定位（可见区顶部 = 菜单栏正下方）
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let width: CGFloat = 300
        let height: CGFloat = max(fittingSize.height, 200)

        // 水平居中于点击位置，左右各留 8pt 间距
        var x = screenPoint.x - width / 2
        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - width - 8)
        // 顶部对齐菜单栏正下方 4pt：把面板顶边放到 visibleFrame.maxY - height - 4
        // （macOS 屏幕坐标系 y 向上，面板顶边 y 坐标 = visibleFrame.maxY - height - 4 等价于"面板顶部距离菜单栏底部 4pt"）
        var y = visibleFrame.maxY - height - 4
        // 万一高度超过可见区，向上贴底
        if y < visibleFrame.minY + 8 {
            y = visibleFrame.minY + 8
        }

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFrontRegardless()

        overviewPanel = panel
        installHoverTracking(on: hosting.view)
        installOutsideClickMonitor()
    }

    /// 安装追踪区域，让鼠标离开面板时自动关闭。
    private func installHoverTracking(on view: NSView) {
        view.trackingAreas.forEach { view.removeTrackingArea($0) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        view.addTrackingArea(area)
    }

    /// 监听面板外的鼠标点击，自动关闭。
    /// - 点击面板本身：忽略（让 SwiftUI 内部按钮处理）
    /// - 点击状态项：忽略（让 togglePopover 处理切换）
    /// - 其他位置：关闭面板
    private func installOutsideClickMonitor() {
        if let existing = outsideClickMonitor {
            NSEvent.removeMonitor(existing)
        }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.overviewPanel else { return event }
            if event.window === panel { return event }
            if let statusWindow = self.statusItem.button?.window, event.window === statusWindow {
                return event
            }
            if !panel.frame.contains(NSEvent.mouseLocation) {
                self.closePopover()
            }
            return event
        }
    }

    /// 鼠标进入面板内容区域：取消挂起的关闭任务。
    @objc func mouseEntered(_ event: NSEvent) {
        cancelPendingClose()
    }

    /// 鼠标离开面板内容区域：稍作宽容后关闭，期间重新进入可取消。
    @objc func mouseExited(_ event: NSEvent) {
        schedulePopoverClose()
    }

    /// 在宽容期后关闭面板与采样。
    private func schedulePopoverClose() {
        cancelPendingClose()
        let work = DispatchWorkItem { [weak self] in
            self?.closePopover()
        }
        pendingCloseTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeGrace, execute: work)
    }

    /// 取消挂起的延迟关闭。
    private func cancelPendingClose() {
        pendingCloseTask?.cancel()
        pendingCloseTask = nil
    }

    /// 真正关闭面板并停止采样。
    private func closePopover() {
        cancelPendingClose()
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
        overviewPanel?.orderOut(nil)
        overviewPanel = nil
        if monitor.isRefreshing {
            monitor.stop()
        }
    }
}

/// 菜单栏弹出的系统资源概览面板。
struct StatusBarOverview: View {
    /// 共享的系统监控数据源。
    @ObservedObject var monitor: SystemMonitor
    /// 跳转到主窗口完整界面的回调。
    var openMain: () -> Void

    /// 已解析的进程图标与展示名缓存，避免每次刷新重复查询。
    @State private var iconCache: [Int: NSImage] = [:]
    @State private var nameCache: [Int: String] = [:]

    /// 按 CPU 使用率排序的前三名进程。
    private var cpuTop3: [RunningProcess] {
        Array(monitor.topProcesses.sorted { $0.cpu > $1.cpu }.prefix(3))
    }

    /// 按内存占用排序的前三名进程。
    private var memTop3: [RunningProcess] {
        Array(monitor.topProcesses.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            Divider()
            cpuSection
            memSection
            Divider()
            openButton
        }
        .padding(14)
        .frame(width: 300)
        .background(WorkbenchTheme.canvas)
    }

    /// 顶部 CPU / 内存大数字概览。
    private var headerRow: some View {
        HStack(spacing: 18) {
            metric(title: "CPU", value: monitor.cpuOverall, color: WorkbenchTheme.cyan)
            metric(title: "内存", value: monitor.memoryUsagePercent, color: WorkbenchTheme.coral)
        }
    }

    /// 单个指标的大数字展示。
    private func metric(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WorkbenchTheme.textSecondary)
            Text(String(format: "%.1f%%", value))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    /// CPU 占用前三名列表。
    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("CPU 占用 Top 3")
            if cpuTop3.isEmpty {
                emptyHint
            } else {
                ForEach(cpuTop3) { p in
                    processRow(process: p, value: String(format: "%.1f%%", p.cpu), color: WorkbenchTheme.cyan)
                }
            }
        }
    }

    /// 内存占用前三名列表，展示真实物理内存大小。
    private var memSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("内存占用 Top 3")
            if memTop3.isEmpty {
                emptyHint
            } else {
                ForEach(memTop3) { p in
                    processRow(process: p, value: Self.formattedBytes(p.memoryBytes), color: WorkbenchTheme.coral)
                }
            }
        }
    }

    /// 分组小标题。
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(WorkbenchTheme.textSecondary)
    }

    /// 暂无采样数据时的占位提示。
    private var emptyHint: some View {
        Text("采样中…")
            .font(.system(size: 12))
            .foregroundStyle(WorkbenchTheme.textTertiary)
    }

    /// 单行进程排名：软件图标 + 名称 + 数值。
    private func processRow(process: RunningProcess, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon(for: process.pid))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .cornerRadius(4)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(for: process))
                    .font(.system(size: 12))
                    .foregroundStyle(WorkbenchTheme.textPrimary)
                    .lineLimit(1)
                Text("#\(process.pid) · \(process.user)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(WorkbenchTheme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    /// 按 PID 解析进程对应的软件图标，未命中时回退到通用可执行文件图标。
    private func icon(for pid: Int) -> NSImage {
        if let cached = iconCache[pid] { return cached }
        let resolved: NSImage
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           let icon = app.icon {
            resolved = icon
        } else {
            resolved = NSWorkspace.shared.icon(for: .executable)
        }
        iconCache[pid] = resolved
        return resolved
    }

    /// 按 PID 解析进程的友好展示名，优先取 App 本地化名，否则用可执行路径的 basename。
    private func displayName(for process: RunningProcess) -> String {
        if let cached = nameCache[process.pid] { return cached }
        let resolved: String
        if let app = NSRunningApplication(processIdentifier: pid_t(process.pid)),
           let localized = app.localizedName, !localized.isEmpty {
            resolved = localized
        } else {
            // 回退：从可执行路径中取最后一段作为展示名，避免出现 "/System/Library/PrivateFra..." 这类长路径。
            if let lastSlash = process.name.lastIndex(of: "/") {
                resolved = String(process.name[process.name.index(after: lastSlash)...])
            } else {
                resolved = process.name
            }
        }
        nameCache[process.pid] = resolved
        return resolved
    }

    /// 将字节数格式化为人类可读的内存大小。
    private static func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }

    /// 跳转到主窗口完整界面的入口。
    private var openButton: some View {
        Button(action: openMain) {
            Text("在 Workbench 中查看")
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .background(WorkbenchTheme.panelRaised)
        .cornerRadius(8)
    }
}