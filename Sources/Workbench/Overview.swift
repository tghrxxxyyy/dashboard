import AppKit
import SwiftUI

/// 汇总启动台、系统状态与保险库状态的全局概览页。
struct OverviewView: View {
    /// 启动台数据源。
    @ObservedObject var launcherStore: LauncherStore
    /// 密钥保险库数据源。
    @ObservedObject var secretsStore: SecretsStore
    /// 系统监控数据源。
    @ObservedObject var monitor: SystemMonitor
    /// 切换到目标工作区的回调。
    let navigate: (WorkbenchSection) -> Void

    /// 页面内容是否已经进入可见状态。
    @State private var contentVisible = false
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WorkbenchTheme.sectionSpacing) {
                snapshotHeader
                    .workbenchReveal(isVisible: contentVisible)

                metricGrid
                    .workbenchReveal(isVisible: contentVisible, delay: 0.04)

                workspaceGrid
                    .workbenchReveal(isVisible: contentVisible, delay: 0.09)

                consoleShortcut
                    .workbenchReveal(isVisible: contentVisible, delay: 0.14)
            }
            .padding(WorkbenchTheme.pagePadding)
            .frame(maxWidth: 1320, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .onAppear(perform: revealContent)
        .onDisappear {
            contentVisible = false
        }
    }

    /// 概览顶部的实时状态摘要。
    private var snapshotHeader: some View {
        HStack(spacing: 12) {
            WorkbenchLiveStatus(title: "SYSTEM SNAPSHOT")

            Rectangle()
                .fill(WorkbenchTheme.separatorStrong)
                .frame(width: 1, height: 14)

            Text("\(launcherStore.tags.count) GROUPS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.textTertiary)

            Text("\(applicationCount) APPS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.textTertiary)

            Spacer()

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(context.date, format: .dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.textSecondary)
            }
        }
        .frame(height: 22)
    }

    /// 三个关键工作区指标卡。
    private var metricGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 196, maximum: 360), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            WorkbenchMetricCard(
                label: "LAUNCHER",
                value: "\(applicationCount)",
                detail: "\(launcherStore.tags.count) 个标签 · 本地应用",
                systemImage: "square.grid.2x2",
                accent: WorkbenchTheme.coral
            ) {
                navigate(.launcher)
            }

            WorkbenchMetricCard(
                label: "CPU LOAD",
                value: String(format: "%.1f%%", monitor.cpuOverall),
                detail: monitor.cpuPerCore.isEmpty ? "正在建立采样基线" : "\(monitor.cpuPerCore.count) 核 · 实时采样",
                systemImage: "waveform.path.ecg",
                accent: WorkbenchTheme.cyan
            ) {
                navigate(.monitor)
            }

            WorkbenchMetricCard(
                label: "SECURE VAULT",
                value: secretsStore.unlocked ? "\(secretsStore.entries.count)" : "LOCKED",
                detail: secretsStore.unlocked ? "保险库已解锁" : "等待主密码",
                systemImage: secretsStore.unlocked ? "lock.open.fill" : "lock.fill",
                accent: WorkbenchTheme.signalYellow
            ) {
                navigate(.secrets)
            }
        }
    }

    /// 启动台快捷入口与系统脉冲组成的主要工作区。
    private var workspaceGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 330), spacing: 14, alignment: .top)],
            alignment: .leading,
            spacing: 14
        ) {
            quickLaunchPanel
            systemPulsePanel
        }
    }

    /// 最近配置应用的快速启动面板。
    private var quickLaunchPanel: some View {
        WorkbenchPanel(accent: WorkbenchTheme.coral) {
            VStack(alignment: .leading, spacing: 16) {
                WorkbenchSectionHeader(
                    eyebrow: "QUICK LAUNCH",
                    title: "应用捷径",
                    trailing: applicationCount == 0 ? nil : "TOP \(min(quickApps.count, 6))",
                    accent: WorkbenchTheme.coral
                )

                if quickApps.isEmpty {
                    WorkbenchEmptyState(
                        systemImage: "app.badge",
                        title: "还没有应用捷径",
                        detail: "在启动台添加第一个本地应用",
                        actionTitle: "前往启动台"
                    ) {
                        navigate(.launcher)
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 148), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(Array(quickApps.prefix(6))) { item in
                            OverviewAppButton(item: item) {
                                launch(item)
                            }
                        }
                    }

                    Button {
                        navigate(.launcher)
                    } label: {
                        Label("查看全部应用", systemImage: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WorkbenchTheme.coral)
                    }
                    .buttonStyle(.plain)
                    .help("打开启动台")
                }
            }
            .frame(minHeight: 274, alignment: .top)
        }
    }

    /// CPU、内存与活跃进程的实时状态面板。
    private var systemPulsePanel: some View {
        WorkbenchPanel(accent: WorkbenchTheme.cyan) {
            VStack(alignment: .leading, spacing: 17) {
                WorkbenchSectionHeader(
                    eyebrow: "SYSTEM PULSE",
                    title: "实时负载",
                    trailing: String(format: "CPU %.1f%%", monitor.cpuOverall),
                    accent: WorkbenchTheme.cyan
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PROCESSOR")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(WorkbenchTheme.textSecondary)
                        Spacer()
                        Text(String(format: "%.1f%%", monitor.cpuOverall))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(WorkbenchTheme.textPrimary)
                    }
                    WorkbenchProgressTrack(value: monitor.cpuOverall / 100, tint: WorkbenchTheme.cyan)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("MEMORY")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(WorkbenchTheme.textSecondary)
                        Spacer()
                        Text(memorySummary)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(WorkbenchTheme.textPrimary)
                    }
                    WorkbenchProgressTrack(value: memoryRatio, tint: WorkbenchTheme.signalYellow)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("CORE ACTIVITY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(WorkbenchTheme.textSecondary)

                    CoreActivityStrip(usages: monitor.cpuPerCore)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("TOP PROCESSES")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(WorkbenchTheme.textSecondary)

                    if monitor.topProcesses.isEmpty {
                        Text("等待进程采样")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WorkbenchTheme.textTertiary)
                            .frame(height: 23)
                    } else {
                        ForEach(Array(monitor.topProcesses.prefix(3))) { process in
                            HStack(spacing: 10) {
                                Text("\(process.pid)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(WorkbenchTheme.textTertiary)
                                    .frame(width: 46, alignment: .leading)

                                Text(process.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(WorkbenchTheme.textPrimary)
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Text(String(format: "%.1f%%", process.cpu))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(WorkbenchTheme.cyan)
                            }
                            .frame(height: 23)
                        }
                    }
                }
            }
            .frame(minHeight: 274, alignment: .top)
        }
    }

    /// 文件与终端工作区的宽幅入口。
    private var consoleShortcut: some View {
        Button {
            navigate(.files)
        } label: {
            HStack(spacing: 15) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WorkbenchTheme.canvas)
                    .frame(width: 38, height: 38)
                    .background(WorkbenchTheme.neon)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("FILES + TERMINAL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(WorkbenchTheme.neon)

                    Text("打开本地控制台")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WorkbenchTheme.textPrimary)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WorkbenchTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(WorkbenchTheme.panel)
            .overlay {
                RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                    .stroke(WorkbenchTheme.neon.opacity(0.24), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("打开文件搜索与终端")
    }

    /// 启动页面首次显现动效，并在 Reduce Motion 开启时立即展示。
    private func revealContent() {
        withAnimation(reduceMotion ? nil : WorkbenchTheme.motionStandard) {
            contentVisible = true
        }
    }

    /// 启动指定应用，并由启动台统一记录最近使用与路径修复结果。
    /// - Parameter item: 需要打开的本地应用条目。
    private func launch(_ item: AppItem) {
        launcherStore.launch(item)
    }

    /// 启动台内配置的应用总数。
    private var applicationCount: Int {
        launcherStore.tags.reduce(0) { $0 + $1.items.count }
    }

    /// 优先展示常用与最近启动应用，其余按分组顺序补齐。
    private var quickApps: [AppItem] {
        var seen = Set<UUID>()
        let prioritized = launcherStore.favoriteApps + launcherStore.recentApps + launcherStore.allApps
        return prioritized.filter { seen.insert($0.id).inserted }
    }

    /// 当前内存占用比例，范围为 0 到 1。
    private var memoryRatio: Double {
        guard let memory = monitor.mem, memory.total > 0 else { return 0 }
        return min(max(Double(memory.used) / Double(memory.total), 0), 1)
    }

    /// 当前内存占用的紧凑文本。
    private var memorySummary: String {
        guard let memory = monitor.mem else { return "WAITING" }
        let used = Double(memory.used) / 1_073_741_824
        let total = Double(memory.total) / 1_073_741_824
        return String(format: "%.1f / %.1f GB", used, total)
    }
}

/// 概览页中的单个应用快捷按钮。
private struct OverviewAppButton: View {
    /// 应用数据。
    let item: AppItem
    /// 打开应用的回调。
    let action: () -> Void

    /// 当前指针是否悬停在按钮上。
    @State private var isHovered = false
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WorkbenchTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isHovered ? WorkbenchTheme.coral : WorkbenchTheme.textTertiary)
                    .offset(x: isHovered && !reduceMotion ? 1 : 0, y: isHovered && !reduceMotion ? -1 : 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(isHovered ? WorkbenchTheme.panelRaised : WorkbenchTheme.overlay(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : WorkbenchTheme.motionQuick) {
                isHovered = hovered
            }
        }
        .help("启动或切换到 \(item.name)")
    }
}

/// 每个 CPU 核心的紧凑活动强度条。
private struct CoreActivityStrip: View {
    /// 每个 CPU 核心的百分比使用率。
    let usages: [Double]
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if usages.isEmpty {
            HStack(spacing: 5) {
                ForEach(0..<8, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(WorkbenchTheme.overlay(0.045))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 18)
        } else {
            HStack(spacing: 5) {
                ForEach(Array(usages.enumerated()), id: \.offset) { index, usage in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(coreColor(for: usage))
                        .frame(maxWidth: .infinity)
                        .help("核心 \(index + 1)：\(Int(usage))%")
                }
            }
            .frame(height: 18)
            .animation(reduceMotion ? nil : WorkbenchTheme.motionStandard, value: usages)
        }
    }

    /// 根据核心负载返回分级语义色。
    /// - Parameter usage: 核心百分比使用率。
    /// - Returns: 对应负载级别的颜色。
    private func coreColor(for usage: Double) -> Color {
        switch usage {
        case 80...:
            return WorkbenchTheme.coral
        case 55..<80:
            return WorkbenchTheme.signalYellow
        default:
            return WorkbenchTheme.cyan.opacity(0.20 + min(max(usage, 0), 100) / 135)
        }
    }
}
