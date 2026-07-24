import SwiftUI
import AppKit

/// Workbench 的全局视觉令牌，统一颜色、尺寸与动效节奏。
///
/// 颜色令牌均为「随 appearance 动态切换」的 `Color`：深色主题下沿用原有高对比深色配色，
/// 浅色主题下自动翻转为对应的浅色配色，从而保证任意主题下对比度一致、文字清晰可读。
enum WorkbenchTheme {
    // MARK: - 动态颜色构造器

    /// 依据当前 appearance 在浅色/深色之间切换的实心表面或文本颜色。
    /// - Parameters:
    ///   - light: 浅色外观下的 RGB 三元组（0...1）。
    ///   - dark: 深色外观下的 RGB 三元组（0...1）。
    /// - Returns: 随外观解析的动态 `Color`。
    static func dynamic(light: (CGFloat, CGFloat, CGFloat),
                        dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// 在深色用白色描边、浅色用黑色描边的半透明分隔/描边色。
    /// - Parameters:
    ///   - lightAlpha: 浅色外观下的不透明度。
    ///   - darkAlpha: 深色外观下的不透明度。
    /// - Returns: 随外观解析的动态 `Color`。
    static func separator(_ lightAlpha: Double, _ darkAlpha: Double) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(isDark ? darkAlpha : lightAlpha)
        })
    }

    /// 在任意表面上的半透明叠加色：深色主题下为「白+透明度」，浅色主题下翻转为「黑+透明度」。
    /// 同一函数即可覆盖「次级文字」与「悬停/描边高亮」——两者在浅色下都需要反转为暗色。
    /// - Parameter alpha: 不透明度，深色与浅色下保持一致。
    /// - Returns: 随外观解析的动态 `Color`。
    static func overlay(_ alpha: Double) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(alpha)
        })
    }

    /// 模态遮罩：深色更暗、浅色更透，保证两种主题下都有合适的前景聚焦感。
    static let scrim = Color(NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor.black.withAlphaComponent(isDark ? 0.62 : 0.34)
    })

    /// 进度轨道未填充部分。
    static let track = separator(0.06, 0.055)

    /// 强调按钮上的前景文字色：亮色强调底上使用深色文字，两种主题均清晰可读。
    static let onAccent = Color(red: 0.043, green: 0.051, blue: 0.047)

    /// 背景画布的 `NSColor` 版本，供原生窗口背景使用。
    static let canvasNS: NSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let c = isDark ? (0.025, 0.031, 0.029) : (0.965, 0.972, 0.968)
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    }

    /// 背景细网格线：深色用白、浅色用黑，保持低对比。
    static let gridFine = Color(NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(isDark ? 0.05 : 0.06)
    })

    // MARK: - 表面与文本（动态）

    /// 应用最底层的画布。
    static let canvas = dynamic(light: (0.965, 0.972, 0.968), dark: (0.025, 0.031, 0.029))
    /// 侧边栏使用的高密度表面。
    static let sidebar = dynamic(light: (0.945, 0.952, 0.948), dark: (0.038, 0.046, 0.043))
    /// 顶部栏使用的表面。
    static let chrome = dynamic(light: (0.952, 0.958, 0.954), dark: (0.045, 0.053, 0.050))
    /// 一级内容面板表面。
    static let panel = dynamic(light: (1.000, 1.000, 1.000), dark: (0.061, 0.071, 0.067))
    /// 悬停或选中时使用的抬升表面。
    static let panelRaised = dynamic(light: (0.933, 0.941, 0.937), dark: (0.082, 0.094, 0.089))
    /// 输入控件使用的表面。
    static let input = dynamic(light: (0.945, 0.952, 0.948), dark: (0.031, 0.039, 0.036))

    /// 主文本颜色。
    static let textPrimary = dynamic(light: (0.078, 0.094, 0.086), dark: (0.950, 0.972, 0.958))
    /// 次级说明文本颜色。
    static let textSecondary = dynamic(light: (0.353, 0.388, 0.365), dark: (0.610, 0.650, 0.625))
    /// 弱提示文本颜色。
    static let textTertiary = dynamic(light: (0.560, 0.592, 0.568), dark: (0.420, 0.455, 0.435))
    /// 通用分隔线颜色。
    static let separator = separator(0.10, 0.085)
    /// 强调分隔线颜色。
    static let separatorStrong = separator(0.18, 0.15)

    /// 核心成功与概览强调色（两种主题下均保持高饱和，确保可辨识）。
    static let neon = Color(red: 0.690, green: 1.000, blue: 0.310)
    /// 启动台与高优先级操作强调色。
    static let coral = Color(red: 1.000, green: 0.390, blue: 0.365)
    /// 系统监控与信息强调色。
    static let cyan = Color(red: 0.220, green: 0.880, blue: 1.000)
    /// 警告与保险库强调色。
    static let signalYellow = Color(red: 1.000, green: 0.790, blue: 0.260)
    /// 工具箱语义强调色。
    static let violet = Color(red: 0.620, green: 0.550, blue: 1.000)

    /// 全局页面边距。
    static let pagePadding: CGFloat = 26
    /// 页面区块间距。
    static let sectionSpacing: CGFloat = 18
    /// 全局最大圆角。
    static let cornerRadius: CGFloat = 8
    /// 侧边栏稳定宽度。
    static let sidebarWidth: CGFloat = 236
    /// 顶部栏稳定高度。
    static let topBarHeight: CGFloat = 86

    /// 按压和悬停反馈使用的快速动效。
    static let motionQuick = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.12)
    /// 控件状态变化使用的标准 Premium 动效。
    static let motionStandard = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.36)
    /// 页面级切换使用的慢速 Premium 动效。
    static let motionPage = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.46)
}

/// Workbench 的深色几何背景，使用细线网格增加空间层次。
struct WorkbenchBackdrop: View {
    var body: some View {
        ZStack {
            WorkbenchTheme.canvas

            Canvas { context, size in
                var fineGrid = Path()
                let gridSize: CGFloat = 44

                // 细网格保持低对比，避免干扰主要内容。
                for x in stride(from: CGFloat.zero, through: size.width, by: gridSize) {
                    fineGrid.move(to: CGPoint(x: x, y: 0))
                    fineGrid.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: CGFloat.zero, through: size.height, by: gridSize) {
                    fineGrid.move(to: CGPoint(x: 0, y: y))
                    fineGrid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(fineGrid, with: .color(WorkbenchTheme.gridFine), lineWidth: 0.5)

                var majorGrid = Path()
                let majorSize = gridSize * 4
                for x in stride(from: CGFloat.zero, through: size.width, by: majorSize) {
                    majorGrid.move(to: CGPoint(x: x, y: 0))
                    majorGrid.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: CGFloat.zero, through: size.height, by: majorSize) {
                    majorGrid.move(to: CGPoint(x: 0, y: y))
                    majorGrid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(majorGrid, with: .color(WorkbenchTheme.neon.opacity(0.022)), lineWidth: 0.75)
            }
        }
        .ignoresSafeArea()
    }
}

/// 带有可选语义色顶线的标准内容面板。
struct WorkbenchPanel<Content: View>: View {
    /// 面板顶部语义强调色。
    let accent: Color?
    /// 面板内部内容。
    private let content: Content

    /// 创建标准内容面板。
    /// - Parameters:
    ///   - accent: 可选的顶部语义强调色。
    ///   - content: 面板内部内容构建器。
    init(accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                    .fill(WorkbenchTheme.panel)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                    .stroke(WorkbenchTheme.separator, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                if let accent {
                    Rectangle()
                        .fill(accent)
                        .frame(height: 2)
                        .padding(.horizontal, 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
    }
}

/// 页面内的统一区块标题。
struct WorkbenchSectionHeader: View {
    /// 区块英文眉题。
    let eyebrow: String
    /// 区块主标题。
    let title: String
    /// 可选的尾部信息。
    var trailing: String?
    /// 区块语义强调色。
    var accent: Color = WorkbenchTheme.neon

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WorkbenchTheme.textPrimary)
            }

            Spacer(minLength: 12)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.textSecondary)
            }
        }
    }
}

/// 可复用的页面级标题，供功能页面保持一致层级。
struct WorkbenchPageHeader<Actions: View>: View {
    /// 页面英文眉题。
    let eyebrow: String
    /// 页面主标题。
    let title: String
    /// 页面简短状态说明。
    let detail: String
    /// 页面语义强调色。
    let accent: Color
    /// 页面右侧操作区。
    private let actions: Actions

    /// 创建页面级标题。
    /// - Parameters:
    ///   - eyebrow: 页面英文眉题。
    ///   - title: 页面主标题。
    ///   - detail: 页面简短状态说明。
    ///   - accent: 页面语义强调色。
    ///   - actions: 页面右侧操作内容构建器。
    init(
        eyebrow: String,
        title: String,
        detail: String,
        accent: Color,
        @ViewBuilder actions: () -> Actions
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.accent = accent
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Rectangle()
                .fill(accent)
                .frame(width: 3, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(WorkbenchTheme.textPrimary)

                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WorkbenchTheme.textSecondary)
                }
            }

            Spacer(minLength: 16)
            actions
        }
    }
}

/// 无右侧操作区的页面标题快捷初始化。
extension WorkbenchPageHeader where Actions == EmptyView {
    /// 创建不包含右侧操作区的页面标题。
    /// - Parameters:
    ///   - eyebrow: 页面英文眉题。
    ///   - title: 页面主标题。
    ///   - detail: 页面简短状态说明。
    ///   - accent: 页面语义强调色。
    init(eyebrow: String, title: String, detail: String, accent: Color) {
        self.init(eyebrow: eyebrow, title: title, detail: detail, accent: accent) {
            EmptyView()
        }
    }
}

/// 概览页使用的可交互指标卡。
struct WorkbenchMetricCard: View {
    /// 指标名称。
    let label: String
    /// 指标主值。
    let value: String
    /// 指标补充信息。
    let detail: String
    /// 指标图标。
    let systemImage: String
    /// 指标语义色。
    let accent: Color
    /// 点击指标后的动作。
    let action: () -> Void

    /// 当前指针是否悬停在指标卡上。
    @State private var isHovered = false
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 30, height: 30)
                        .background(accent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isHovered ? accent : WorkbenchTheme.textTertiary)
                        .offset(x: isHovered && !reduceMotion ? 1 : 0, y: isHovered && !reduceMotion ? -1 : 0)
                }

                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.textSecondary)

                Text(value)
                    .font(.system(size: 27, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(WorkbenchTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WorkbenchTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
            .background(isHovered ? WorkbenchTheme.panelRaised : WorkbenchTheme.panel)
            .overlay {
                RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                    .stroke(isHovered ? accent.opacity(0.42) : WorkbenchTheme.separator, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            .shadow(color: accent.opacity(isHovered ? 0.10 : 0), radius: 16, y: 6)
            .scaleEffect(isHovered && !reduceMotion ? 1.008 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : WorkbenchTheme.motionQuick) {
                isHovered = hovered
            }
        }
    }
}

/// 标准图标操作按钮，适合工具栏中的单一命令。
struct WorkbenchIconButton: View {
    /// SF Symbol 图标名称。
    let systemImage: String
    /// 悬停帮助文本与辅助功能标签。
    let help: String
    /// 按钮语义色。
    var tint: Color = WorkbenchTheme.textSecondary
    /// 点击按钮后的动作。
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 30)
        }
        .buttonStyle(WorkbenchIconButtonStyle(tint: tint))
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 图标按钮的统一悬停与按压样式。
private struct WorkbenchIconButtonStyle: ButtonStyle {
    /// 按钮语义色。
    let tint: Color
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 构造图标按钮的交互外观。
    /// - Parameter configuration: SwiftUI 提供的按钮当前状态。
    /// - Returns: 带有按压反馈的按钮内容。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? tint : WorkbenchTheme.textSecondary)
            .background(configuration.isPressed ? tint.opacity(0.14) : WorkbenchTheme.panelRaised)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(WorkbenchTheme.separator, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : WorkbenchTheme.motionQuick, value: configuration.isPressed)
    }
}

/// 带图标的高优先级操作按钮样式。
struct WorkbenchAccentButtonStyle: ButtonStyle {
    /// 按钮语义色。
    let tint: Color
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 构造高优先级按钮的交互外观。
    /// - Parameter configuration: SwiftUI 提供的按钮当前状态。
    /// - Returns: 带高对比填充和按压反馈的按钮内容。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WorkbenchTheme.onAccent)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(tint.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : WorkbenchTheme.motionQuick, value: configuration.isPressed)
    }
}

/// 无内容场景的紧凑占位状态。
struct WorkbenchEmptyState: View {
    /// 空状态图标。
    let systemImage: String
    /// 空状态标题。
    let title: String
    /// 空状态补充信息。
    let detail: String
    /// 可选操作标题。
    var actionTitle: String?
    /// 可选操作回调。
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(WorkbenchTheme.textTertiary)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WorkbenchTheme.textPrimary)

            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WorkbenchTheme.textSecondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(WorkbenchAccentButtonStyle(tint: WorkbenchTheme.neon))
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 142)
    }
}

/// 紧凑的键盘快捷键标记。
struct WorkbenchKeycap: View {
    /// 需要显示的快捷键文本。
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(WorkbenchTheme.textTertiary)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(WorkbenchTheme.input)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(WorkbenchTheme.separatorStrong, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// 持续显示本地服务状态的呼吸指示器。
struct WorkbenchLiveStatus: View {
    /// 状态标题。
    var title: String = "LOCAL ONLINE"
    /// 呼吸动效当前状态。
    @State private var isPulsing = false
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(WorkbenchTheme.neon.opacity(isPulsing ? 0.06 : 0.20))
                    .frame(width: 15, height: 15)
                    .scaleEffect(isPulsing && !reduceMotion ? 1.28 : 0.84)

                Circle()
                    .fill(WorkbenchTheme.neon)
                    .frame(width: 6, height: 6)
                    .shadow(color: WorkbenchTheme.neon.opacity(0.55), radius: 5)
            }

            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.textSecondary)
        }
        .onAppear(perform: updatePulseAnimation)
        .onChange(of: reduceMotion) { _, _ in
            updatePulseAnimation()
        }
    }

    /// 根据系统 Reduce Motion 设置启动或停止状态呼吸动效。
    private func updatePulseAnimation() {
        if reduceMotion {
            withAnimation(nil) {
                isPulsing = false
            }
            return
        }

        // 重设后再启动循环，确保动态偏好切换可以立即生效。
        isPulsing = false
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

/// 统一的百分比进度轨道。
struct WorkbenchProgressTrack: View {
    /// 取值范围为 0 到 1 的进度。
    let value: Double
    /// 进度语义色。
    let tint: Color
    /// 轨道高度。
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(WorkbenchTheme.track)

                Rectangle()
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(clampedValue))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: min(height / 2, 3), style: .continuous))
        .accessibilityValue(Text("\(Int(clampedValue * 100))%"))
    }

    /// 将外部进度约束在可显示的 0 到 1 范围内。
    private var clampedValue: Double {
        min(max(value, 0), 1)
    }
}

/// 页面切换使用的短距离位移与透明度组合。
private struct WorkbenchPageTransitionModifier: ViewModifier {
    /// 内容透明度。
    let opacity: Double
    /// 内容纵向位移。
    let offset: CGFloat

    /// 构造页面过渡状态。
    /// - Parameter content: 需要应用过渡的页面内容。
    /// - Returns: 应用位移与透明度后的内容。
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offset)
    }
}

extension AnyTransition {
    /// Workbench 页面统一的 Premium 进入与离开过渡。
    static var workbenchPage: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: WorkbenchPageTransitionModifier(opacity: 0, offset: 10),
                identity: WorkbenchPageTransitionModifier(opacity: 1, offset: 0)
            ),
            removal: .modifier(
                active: WorkbenchPageTransitionModifier(opacity: 0, offset: -5),
                identity: WorkbenchPageTransitionModifier(opacity: 1, offset: 0)
            )
        )
    }
}

/// 内容首次出现时使用的轻量级错峰显现效果。
private struct WorkbenchRevealModifier: ViewModifier {
    /// 当前内容是否已经进入可见状态。
    let isVisible: Bool
    /// 相对页面进入的延迟秒数。
    let delay: Double
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 构造内容显现状态。
    /// - Parameter content: 需要应用显现效果的内容。
    /// - Returns: 应用透明度、短位移和动效后的内容。
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 10)
            .animation(
                reduceMotion ? nil : WorkbenchTheme.motionStandard.delay(delay),
                value: isVisible
            )
    }
}

extension View {
    /// 为页面内容添加可访问的错峰显现效果。
    /// - Parameters:
    ///   - isVisible: 内容是否进入可见状态。
    ///   - delay: 相对页面进入的延迟秒数。
    /// - Returns: 应用显现效果后的视图。
    func workbenchReveal(isVisible: Bool, delay: Double = 0) -> some View {
        modifier(WorkbenchRevealModifier(isVisible: isVisible, delay: delay))
    }
}

/// Workbench 的主题管理器，统一管理「跟随系统 / 浅色 / 深色」三种模式，
/// 并将选择持久化到 UserDefaults，应用重启后自动恢复。
@MainActor
final class ThemeManager: ObservableObject {
    /// 单一共享实例，供界面与 AppDelegate 共用。
    static let shared = ThemeManager()

    /// 可选的主题模式。
    enum Mode: String, CaseIterable, Identifiable {
        /// 跟随 macOS 系统外观。
        case system
        /// 强制浅色。
        case light
        /// 强制深色。
        case dark

        /// 稳定标识。
        var id: String { rawValue }

        /// 中文标签。
        var label: String {
            switch self {
            case .system: "跟随系统"
            case .light: "浅色"
            case .dark: "深色"
            }
        }

        /// 顶部栏控件使用的 SF Symbol。
        var symbol: String {
            switch self {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max.fill"
            case .dark: "moon.fill"
            }
        }

        /// 对应的 NSAppearance；system 返回 nil 以跟随系统。
        var appearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }

        /// 对应的 SwiftUI ColorScheme；system 返回 nil 以跟随系统。
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    /// 当前主题模式，变更时自动持久化并刷新外观。
    @Published var mode: Mode = .system {
        didSet {
            persist()
            applyAppearance()
        }
    }

    /// 需要随主题刷新外观的窗口。
    private weak var window: NSWindow?

    /// 主题持久化键。
    private let defaultsKey = "workbench.themeMode"

    private init() {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)
        self.mode = Mode(rawValue: raw ?? "") ?? .system
    }

    /// 绑定主窗口，并在后续主题变更时同步其外观与背景色。
    /// - Parameter window: 应用主窗口。
    func attach(_ window: NSWindow) {
        self.window = window
        applyAppearance()
    }

    /// 持久化当前模式到 UserDefaults。
    private func persist() {
        UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
    }

    /// 将当前模式应用到全局与主窗口外观。
    private func applyAppearance() {
        let appearance = mode.appearance
        NSApp.appearance = appearance
        if let window {
            window.appearance = appearance
            window.backgroundColor = WorkbenchTheme.canvasNS
        }
    }
}
