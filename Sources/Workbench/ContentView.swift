import SwiftUI

/// Workbench 顶层工作区导航定义。
enum WorkbenchSection: String, CaseIterable, Identifiable, Hashable {
    /// 汇总关键状态与快捷入口。
    case overview
    /// 管理并启动本地应用。
    case launcher
    /// 查看系统资源与进程。
    case monitor
    /// 管理本地加密密钥。
    case secrets
    /// 搜索文件并执行命令。
    case files
    /// 本地工具集：编解码、端口与剪贴板。
    case tools

    /// 导航项稳定标识。
    var id: String { rawValue }

    /// 导航项中文标题。
    var title: String {
        switch self {
        case .overview: "概览"
        case .launcher: "启动台"
        case .monitor: "运行监控"
        case .secrets: "密钥管理"
        case .files: "文件与终端"
        case .tools: "工具"
        }
    }

    /// 顶部栏使用的英文眉题。
    var eyebrow: String {
        switch self {
        case .overview: "OVERVIEW"
        case .launcher: "LAUNCHER"
        case .monitor: "SYSTEM MONITOR"
        case .secrets: "SECURE VAULT"
        case .files: "FILES + TERMINAL"
        case .tools: "TOOLBOX"
        }
    }

    /// 工作区紧凑状态说明。
    var subtitle: String {
        switch self {
        case .overview: "全局态势与快捷入口"
        case .launcher: "应用、标签与工作流"
        case .monitor: "系统资源与活跃进程"
        case .secrets: "本地加密凭据"
        case .files: "搜索、命令与上下文"
        case .tools: "编码、端口与剪贴板"
        }
    }

    /// 导航项使用的 SF Symbol。
    var systemImage: String {
        switch self {
        case .overview: "command"
        case .launcher: "square.grid.2x2"
        case .monitor: "waveform.path.ecg"
        case .secrets: "lock.shield"
        case .files: "terminal"
        case .tools: "wrench.and.screwdriver"
        }
    }

    /// 工作区语义强调色。
    var accent: Color {
        switch self {
        case .overview: WorkbenchTheme.neon
        case .launcher: WorkbenchTheme.coral
        case .monitor: WorkbenchTheme.cyan
        case .secrets: WorkbenchTheme.signalYellow
        case .files: WorkbenchTheme.neon
        case .tools: WorkbenchTheme.violet
        }
    }

    /// 导航项对应的 Command 数字快捷键。
    var keyEquivalent: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .launcher: "2"
        case .monitor: "3"
        case .secrets: "4"
        case .files: "5"
        case .tools: "6"
        }
    }

    /// 用于界面展示的快捷键文本。
    var shortcutLabel: String {
        switch self {
        case .overview: "⌘1"
        case .launcher: "⌘2"
        case .monitor: "⌘3"
        case .secrets: "⌘4"
        case .files: "⌘5"
        case .tools: "⌘6"
        }
    }
}

/// Workbench 的根视图，负责全局状态、导航与命令面板。
struct ContentView: View {
    /// 启动台全局数据源。
    @StateObject private var launcherStore = LauncherStore()
    /// 密钥保险库全局数据源。
    @StateObject private var secretsStore = SecretsStore()
    /// 系统监控全局数据源。
    @StateObject private var monitor = SystemMonitor()
    /// 全局主题管理器（深色 / 浅色 / 跟随系统）。
    @StateObject private var themeManager = ThemeManager.shared

    /// 当前选中的工作区。
    @State private var selectedSection = WorkbenchSection.overview
    /// 命令面板是否显示。
    @State private var commandPalettePresented = false
    /// 命令面板当前搜索文本。
    @State private var commandQuery = ""
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WorkbenchBackdrop()

            HStack(spacing: 0) {
                WorkbenchSidebar(
                    selection: selectedSection,
                    onSelect: navigate
                )

                detailShell
            }

            if commandPalettePresented {
                commandPaletteOverlay
                    .zIndex(10)
            }
        }
        .frame(minWidth: 1040, minHeight: 680)
        .preferredColorScheme(themeManager.mode.colorScheme)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            // 根级维持同一份采样，使概览与监控页共享连续数据。
            monitor.start()
        }
        .onDisappear {
            monitor.stop()
        }
    }

    /// 包含顶部标题与活动页面的详情壳层。
    private var detailShell: some View {
        VStack(spacing: 0) {
            topBar

            ZStack {
                activeSection
                    .id(selectedSection)
                    .transition(reduceMotion ? .opacity : .workbenchPage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkbenchTheme.canvas.opacity(0.72))
    }

    /// 当前工作区对应的功能页面。
    @ViewBuilder
    private var activeSection: some View {
        switch selectedSection {
        case .overview:
            OverviewView(
                launcherStore: launcherStore,
                secretsStore: secretsStore,
                monitor: monitor,
                navigate: navigate
            )
        case .launcher:
            LauncherView(store: launcherStore)
        case .monitor:
            MonitorView(monitor: monitor)
        case .secrets:
            SecretsView(store: secretsStore)
        case .files:
            FilesTerminalView()
        case .tools:
            ToolsView()
        }
    }

    /// 当前工作区的固定顶部标题栏。
    private var topBar: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(selectedSection.accent)
                .frame(width: 3, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedSection.eyebrow)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(selectedSection.accent)

                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text(selectedSection.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(WorkbenchTheme.textPrimary)

                    Text(selectedSection.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WorkbenchTheme.textSecondary)
                }
            }

            Spacer(minLength: 18)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(context.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.textTertiary)
                    .frame(width: 90, alignment: .trailing)
            }

            WorkbenchCommandTrigger(action: presentCommandPalette)

            WorkbenchThemeSwitcher(theme: themeManager)
        }
        .padding(.top, 22)
        .padding(.horizontal, WorkbenchTheme.pagePadding)
        .frame(height: WorkbenchTheme.topBarHeight)
        .background(WorkbenchTheme.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WorkbenchTheme.separator)
                .frame(height: 1)
        }
    }

    /// 覆盖主界面的命令面板与遮罩。
    private var commandPaletteOverlay: some View {
        ZStack(alignment: .top) {
            WorkbenchTheme.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissCommandPalette)

            WorkbenchCommandPalette(
                query: $commandQuery,
                isPresented: $commandPalettePresented,
                currentSection: selectedSection,
                onSelect: navigate
            )
            .padding(.top, 112)
            .transition(.scale(scale: 0.985, anchor: .top).combined(with: .opacity))
        }
        .transition(.opacity)
    }

    /// 切换到指定工作区并关闭命令面板。
    /// - Parameter section: 需要显示的目标工作区。
    private func navigate(to section: WorkbenchSection) {
        let animation = reduceMotion ? nil : WorkbenchTheme.motionPage
        withAnimation(animation) {
            selectedSection = section
            commandPalettePresented = false
        }
    }

    /// 清空查询并显示 Command+K 命令面板。
    private func presentCommandPalette() {
        commandQuery = ""
        withAnimation(reduceMotion ? nil : WorkbenchTheme.motionStandard) {
            commandPalettePresented = true
        }
    }

    /// 关闭命令面板并保留当前工作区。
    private func dismissCommandPalette() {
        withAnimation(reduceMotion ? nil : WorkbenchTheme.motionStandard) {
            commandPalettePresented = false
        }
    }
}

/// 固定在窗口左侧的品牌导航栏。
private struct WorkbenchSidebar: View {
    /// 当前选中的工作区。
    let selection: WorkbenchSection
    /// 切换工作区的回调。
    let onSelect: (WorkbenchSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader

            Rectangle()
                .fill(WorkbenchTheme.separator)
                .frame(height: 1)

            Text("WORKSPACE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.textTertiary)
                .padding(.horizontal, 17)
                .padding(.top, 22)
                .padding(.bottom, 9)

            VStack(spacing: 4) {
                ForEach(WorkbenchSection.allCases) { section in
                    WorkbenchSidebarRow(
                        section: section,
                        isSelected: selection == section
                    ) {
                        onSelect(section)
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 24)

            sidebarFooter
        }
        .frame(width: WorkbenchTheme.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(WorkbenchTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(WorkbenchTheme.separator)
                .frame(width: 1)
        }
    }

    /// Workbench 品牌标识与产品名称。
    private var brandHeader: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(WorkbenchTheme.input)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(WorkbenchTheme.neon.opacity(0.62), lineWidth: 1)
                    }

                Text("W")
                    .font(.system(size: 17, weight: .black, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.neon)
            }
            .frame(width: 36, height: 36)
            .shadow(color: WorkbenchTheme.neon.opacity(0.12), radius: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text("WORKBENCH")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.textPrimary)

                Text("LOCAL CONTROL")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.textTertiary)
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 23)
        .frame(height: WorkbenchTheme.topBarHeight, alignment: .center)
    }

    /// 侧边栏底部的本地运行状态。
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 13) {
            WorkbenchLiveStatus()

            HStack {
                Text("MACOS 14+")
                Spacer()
                Text("ARM64")
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(WorkbenchTheme.textTertiary)
        }
        .padding(15)
        .background(WorkbenchTheme.input.opacity(0.72))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WorkbenchTheme.separator)
                .frame(height: 1)
        }
    }
}

/// 侧边栏中的单个可交互导航项。
private struct WorkbenchSidebarRow: View {
    /// 对应的工作区。
    let section: WorkbenchSection
    /// 当前工作区是否选中。
    let isSelected: Bool
    /// 选择该工作区的回调。
    let action: () -> Void

    /// 当前指针是否悬停在导航项上。
    @State private var isHovered = false
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected || isHovered ? section.accent : WorkbenchTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(section.accent.opacity(isSelected ? 0.12 : 0))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(section.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? WorkbenchTheme.textPrimary : WorkbenchTheme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(section.shortcutLabel)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isHovered || isSelected ? WorkbenchTheme.textTertiary : .clear)
            }
            .padding(.horizontal, 8)
            .frame(height: 42)
            .background(rowBackground)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(section.accent)
                        .frame(width: 2, height: 22)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(section.keyEquivalent, modifiers: .command)
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : WorkbenchTheme.motionQuick) {
                isHovered = hovered
            }
        }
        .help("打开\(section.title)")
    }

    /// 根据选择和悬停状态返回导航项背景色。
    private var rowBackground: Color {
        if isSelected {
            return section.accent.opacity(0.085)
        }
        if isHovered {
            return WorkbenchTheme.overlay(0.040)
        }
        return .clear
    }
}

/// 顶部栏中的 Command+K 命令面板触发器。
private struct WorkbenchCommandTrigger: View {
    /// 显示命令面板的回调。
    let action: () -> Void
    /// 当前指针是否悬停在按钮上。
    @State private var isHovered = false
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "command")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isHovered ? WorkbenchTheme.neon : WorkbenchTheme.textSecondary)

                Text("命令")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WorkbenchTheme.textPrimary)

                WorkbenchKeycap(text: "⌘K")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isHovered ? WorkbenchTheme.panelRaised : WorkbenchTheme.panel)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isHovered ? WorkbenchTheme.neon.opacity(0.30) : WorkbenchTheme.separator, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("k", modifiers: .command)
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : WorkbenchTheme.motionQuick) {
                isHovered = hovered
            }
        }
        .help("打开命令面板")
    }
}

/// 可搜索并支持方向键选择的全局命令面板。
private struct WorkbenchCommandPalette: View {
    /// 命令搜索文本。
    @Binding var query: String
    /// 命令面板是否显示。
    @Binding var isPresented: Bool
    /// 打开命令面板前所在的工作区。
    let currentSection: WorkbenchSection
    /// 选择工作区后的回调。
    let onSelect: (WorkbenchSection) -> Void

    /// 当前键盘或指针高亮的工作区。
    @State private var highlightedSection: WorkbenchSection?
    /// 命令搜索框焦点。
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WorkbenchTheme.neon)

                TextField("搜索工作区", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WorkbenchTheme.textPrimary)
                    .focused($searchFocused)
                    .onSubmit(performHighlightedSelection)

                WorkbenchKeycap(text: "ESC")
            }
            .padding(.horizontal, 18)
            .frame(height: 58)

            Rectangle()
                .fill(WorkbenchTheme.separatorStrong)
                .frame(height: 1)

            if filteredSections.isEmpty {
                WorkbenchEmptyState(
                    systemImage: "command",
                    title: "没有匹配的工作区",
                    detail: "调整搜索关键词"
                )
                .padding(10)
            } else {
                VStack(spacing: 4) {
                    ForEach(filteredSections) { section in
                        WorkbenchCommandRow(
                            section: section,
                            isCurrent: section == currentSection,
                            isHighlighted: section == highlightedSection,
                            onHover: { highlightedSection = section },
                            action: { select(section) }
                        )
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 530)
        .background(WorkbenchTheme.chrome)
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                .stroke(WorkbenchTheme.neon.opacity(0.28), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.58), radius: 36, y: 18)
        .onAppear(perform: prepareForPresentation)
        .onChange(of: query) { _, _ in
            highlightedSection = filteredSections.first
        }
        .onMoveCommand(perform: moveHighlight)
        .onExitCommand(perform: dismiss)
    }

    /// 根据命令搜索文本过滤工作区。
    private var filteredSections: [WorkbenchSection] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return WorkbenchSection.allCases }
        return WorkbenchSection.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(normalized)
                || $0.eyebrow.localizedCaseInsensitiveContains(normalized)
                || $0.subtitle.localizedCaseInsensitiveContains(normalized)
        }
    }

    /// 聚焦搜索框并初始化当前高亮项。
    private func prepareForPresentation() {
        highlightedSection = filteredSections.first ?? currentSection

        // 延迟到面板进入视图层级后再请求焦点。
        DispatchQueue.main.async {
            searchFocused = true
        }
    }

    /// 使用方向键在当前过滤结果中移动高亮项。
    /// - Parameter direction: 用户触发的方向键移动方向。
    private func moveHighlight(_ direction: MoveCommandDirection) {
        let sections = filteredSections
        guard !sections.isEmpty else { return }

        let currentIndex = highlightedSection.flatMap { sections.firstIndex(of: $0) } ?? 0
        switch direction {
        case .down, .right:
            highlightedSection = sections[(currentIndex + 1) % sections.count]
        case .up, .left:
            highlightedSection = sections[(currentIndex - 1 + sections.count) % sections.count]
        @unknown default:
            break
        }
    }

    /// 执行当前高亮工作区的跳转。
    private func performHighlightedSelection() {
        guard let section = highlightedSection ?? filteredSections.first else { return }
        select(section)
    }

    /// 选择目标工作区并关闭命令面板。
    /// - Parameter section: 用户选中的工作区。
    private func select(_ section: WorkbenchSection) {
        onSelect(section)
        isPresented = false
    }

    /// 响应 Escape 键关闭命令面板。
    private func dismiss() {
        isPresented = false
    }
}

/// 命令面板中的单个工作区结果。
private struct WorkbenchCommandRow: View {
    /// 对应工作区。
    let section: WorkbenchSection
    /// 工作区当前是否已经打开。
    let isCurrent: Bool
    /// 工作区当前是否高亮。
    let isHighlighted: Bool
    /// 指针进入结果时的回调。
    let onHover: () -> Void
    /// 选择结果后的回调。
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(section.accent)
                    .frame(width: 34, height: 34)
                    .background(section.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WorkbenchTheme.textPrimary)

                    Text(section.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WorkbenchTheme.textSecondary)
                }

                Spacer()

                if isCurrent {
                    Text("CURRENT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(section.accent)
                }

                WorkbenchKeycap(text: section.shortcutLabel)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(isHighlighted ? WorkbenchTheme.panelRaised : .clear)
            .overlay(alignment: .leading) {
                if isHighlighted {
                    Rectangle()
                        .fill(section.accent)
                        .frame(width: 2, height: 26)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            if hovered {
                onHover()
            }
        }
    }
}

/// 顶部栏右侧的主题切换控件（跟随系统 / 浅色 / 深色）。
private struct WorkbenchThemeSwitcher: View {
    /// 全局主题管理器。
    @ObservedObject var theme: ThemeManager

    var body: some View {
        Picker("", selection: $theme.mode) {
            ForEach(ThemeManager.Mode.allCases) { mode in
                Image(systemName: mode.symbol)
                    .accessibilityLabel(mode.label)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 104)
        .help("切换主题：系统 / 浅色 / 深色")
    }
}
