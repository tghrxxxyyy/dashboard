import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 菜单栏状态项控制器：在系统状态栏常驻 Workbench 图标，点击弹出资源概览。
@MainActor
final class StatusBarController {
    /// 系统状态栏的常驻条目。
    private let statusItem: NSStatusItem
    /// 承载概览面板的弹出层。
    private let popover = NSPopover()
    /// 概览面板使用的数据源。
    private let monitor = SystemMonitor()
    /// 主窗口引用，用于从概览跳转回完整界面。
    private weak var mainWindow: NSWindow?
    /// 鼠标离开 popover 后到真正关闭的宽容期，方便用户短暂移出再回来。
    private static let closeGrace: TimeInterval = 0.15
    /// 计划中的延迟关闭任务，便于鼠标重新进入时取消。
    private var pendingCloseTask: DispatchWorkItem?

    /// 创建状态项并绑定弹出行为。
    /// - Parameter mainWindow: 主窗口引用，用于概览中跳转到完整界面。
    init(mainWindow: NSWindow?) {
        self.mainWindow = mainWindow
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            let symbol = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Workbench 概览")?
                .withSymbolConfiguration(config)
            symbol?.isTemplate = true
            button.image = symbol
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: StatusBarOverview(monitor: monitor, openMain: { [weak mainWindow] in
                mainWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            })
        )
        // 让 popover 精确贴合 SwiftUI 内容尺寸，避免默认尺寸与渲染尺寸不一致导致的整体错位。
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = .intrinsicContentSize
        }
        popover.contentViewController = hosting
    }

    /// 切换概览面板的显示与隐藏，并在关闭时停止采样以节省资源。
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        cancelPendingClose()
        if popover.isShown {
            closePopover()
            return
        }
        monitor.start()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installHoverTracking()
    }

    /// 安装追踪区域，让鼠标离开 popover 时自动关闭。
    private func installHoverTracking() {
        guard let contentView = popover.contentViewController?.view else { return }
        contentView.trackingAreas.forEach { contentView.removeTrackingArea($0) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        contentView.addTrackingArea(area)
    }

    /// 鼠标进入 popover 内容区域：取消挂起的关闭任务。
    @objc func mouseEntered(_ event: NSEvent) {
        cancelPendingClose()
    }

    /// 鼠标离开 popover 内容区域：稍作宽容后关闭，期间重新进入可取消。
    @objc func mouseExited(_ event: NSEvent) {
        schedulePopoverClose()
    }

    /// 在宽容期后关闭 popover 与采样。
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

    /// 真正关闭 popover 并停止采样。
    private func closePopover() {
        cancelPendingClose()
        if popover.isShown {
            popover.performClose(nil)
        }
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