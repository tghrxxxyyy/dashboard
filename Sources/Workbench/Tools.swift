import SwiftUI
import AppKit
import CommonCrypto

// MARK: - 共享小组件

/// 带短暂「已复制」反馈的复制按钮。
private struct CopyButton: View {
    /// 需要复制到剪贴板的文本。
    let text: String
    /// 复制成功后的瞬时提示状态。
    @State private var done = false

    var body: some View {
        Button {
            if copyToPasteboard(text) {
                done = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { done = false }
            }
        } label: {
            Image(systemName: done ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(done ? WorkbenchTheme.neon : WorkbenchTheme.textSecondary)
                .frame(width: 32, height: 30)
        }
        .buttonStyle(.plain)
        .help(done ? "已复制" : "复制结果")
    }
}

/// 统一的等宽输入文本编辑器。
private struct MonoEditor: View {
    /// 双向绑定的文本内容。
    @Binding var text: String
    /// 占位提示文本。
    let placeholder: String
    /// 编辑器最小高度。
    var minHeight: CGFloat = 120

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
            }
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
        }
        .frame(minHeight: minHeight)
        .background(WorkbenchTheme.input)
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                .stroke(WorkbenchTheme.separator, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
    }
}

/// 带标题与复制按钮的只读结果区。
private struct ResultBox: View {
    /// 需要展示的结果文本。
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(14)
        }
        .frame(minHeight: 120, maxHeight: 320)
        .background(WorkbenchTheme.input)
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                .stroke(WorkbenchTheme.separator, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            CopyButton(text: text)
                .padding(6)
        }
    }
}

// MARK: - 工具集 Hub

/// 工具箱内可切换的具体工具。
enum ToolKind: String, CaseIterable, Identifiable {
    /// 编解码与单位换算。
    case devcalc
    /// 端口与进程管家。
    case portpilot
    /// 剪贴板历史。
    case clipboard

    /// 稳定标识。
    var id: String { rawValue }

    /// 中文标题。
    var title: String {
        switch self {
        case .devcalc: "编解码换算"
        case .portpilot: "端口管家"
        case .clipboard: "剪贴板历史"
        }
    }

    /// SF Symbol 图标。
    var systemImage: String {
        switch self {
        case .devcalc: "function"
        case .portpilot: "network"
        case .clipboard: "doc.on.clipboard"
        }
    }
}

/// 工具箱总入口：内部子导航切换三个实用工具。
struct ToolsView: View {
    /// 当前选中的工具。
    @State private var selection: ToolKind = .devcalc
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            toolSwitcher
                .padding(.horizontal, WorkbenchTheme.pagePadding)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Divider()
                .padding(.horizontal, WorkbenchTheme.pagePadding)

            switch selection {
            case .devcalc: DevCalcView()
            case .portpilot: PortPilotView()
            case .clipboard: ClipboardView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 顶部胶囊式子导航。
    private var toolSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(ToolKind.allCases) { kind in
                Button {
                    withAnimation(reduceMotion ? nil : WorkbenchTheme.motionQuick) {
                        selection = kind
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                        Text(kind.title)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(selection == kind ? WorkbenchTheme.onAccent : WorkbenchTheme.textSecondary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 9)
                    .background(selection == kind ? WorkbenchTheme.violet : WorkbenchTheme.panel)
                    .overlay {
                        if selection != kind {
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .stroke(WorkbenchTheme.separator, lineWidth: 1)
                        }
                    }
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(kind.title)
            }
            Spacer(minLength: 8)
        }
    }
}

// MARK: - DevCalc

/// DevCalc 内置的具体换算器。
private enum CalcKind: String, CaseIterable, Identifiable {
    case base64, url, hash, jwt, timestamp, json, unit

    /// 稳定标识。
    var id: String { rawValue }

    /// 中文标题。
    var title: String {
        switch self {
        case .base64: "Base64"
        case .url: "URL 编解码"
        case .hash: "哈希摘要"
        case .jwt: "JWT 解析"
        case .timestamp: "时间戳转换"
        case .json: "JSON 格式化"
        case .unit: "单位换算"
        }
    }

    /// SF Symbol 图标。
    var systemImage: String {
        switch self {
        case .base64: "arrow.left.arrow.right"
        case .url: "link"
        case .hash: "number"
        case .jwt: "key.horizontal"
        case .timestamp: "clock"
        case .json: "curlybraces"
        case .unit: "scalemass"
        }
    }

    /// 子工具语义色。
    var accent: Color {
        switch self {
        case .base64: WorkbenchTheme.violet
        case .url: WorkbenchTheme.cyan
        case .hash: WorkbenchTheme.coral
        case .jwt: WorkbenchTheme.signalYellow
        case .timestamp: WorkbenchTheme.neon
        case .json: WorkbenchTheme.cyan
        case .unit: WorkbenchTheme.violet
        }
    }
}

/// 编解码 / 单位换算工具主页。
private struct DevCalcView: View {
    /// 当前选中的子工具。
    @State private var calc: CalcKind = .base64

    var body: some View {
        HStack(spacing: 0) {
            // 左侧子工具列表
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(CalcKind.allCases) { kind in
                        Button {
                            withAnimation(WorkbenchTheme.motionQuick) { calc = kind }
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: kind.systemImage)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(calc == kind ? kind.accent : WorkbenchTheme.textSecondary)
                                    .frame(width: 30, height: 30)
                                    .background(calc == kind ? kind.accent.opacity(0.12) : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                Text(kind.title)
                                    .font(.system(size: 12, weight: calc == kind ? .semibold : .medium))
                                    .foregroundStyle(calc == kind ? WorkbenchTheme.textPrimary : WorkbenchTheme.textSecondary)
                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 44)
                            .background(calc == kind ? WorkbenchTheme.panelRaised : .clear)
                            .overlay(alignment: .leading) {
                                if calc == kind {
                                    Rectangle()
                                        .fill(kind.accent)
                                        .frame(width: 2, height: 22)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .frame(width: 200)
            .background(WorkbenchTheme.panel.opacity(0.4))

            Divider()

            // 右侧工作区
            ScrollView {
                switch calc {
                case .base64: Base64Tool()
                case .url: URLTool()
                case .hash: HashTool()
                case .jwt: JWTTool()
                case .timestamp: TimestampTool()
                case .json: JSONTool()
                case .unit: UnitTool()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(WorkbenchTheme.pagePadding)
    }
}

/// 统一包裹单个换算器的面板与标题。
private struct CalcShell<Content: View>: View {
    /// 子工具语义色。
    let accent: Color
    /// 眉题。
    let eyebrow: String
    /// 主标题。
    let title: String
    /// 内部内容。
    let content: Content

    /// 创建换算器外壳。
    init(accent: Color, eyebrow: String, title: String, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.eyebrow = eyebrow
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkbenchSectionHeader(eyebrow: eyebrow, title: title, accent: accent)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                .fill(WorkbenchTheme.panel)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                .stroke(WorkbenchTheme.separator, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
    }
}

// MARK: Base64

/// Base64 编码 / 解码工具。
private struct Base64Tool: View {
    /// 输入文本。
    @State private var input = ""
    /// 输出文本。
    @State private var output = ""
    /// 当前模式。
    @State private var mode: Mode = .encode
    /// 是否使用 URL 安全的字母表。
    @State private var urlSafe = false

    /// 编码 / 解码模式。
    private enum Mode: String, CaseIterable, Identifiable {
        case encode, decode
        var id: String { rawValue }
        var title: String { self == .encode ? "编码" : "解码" }
    }

    var body: some View {
        CalcShell(accent: CalcKind.base64.accent, eyebrow: "BASE64", title: "Base64 编码 / 解码") {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .padding(.bottom, 4)

            MonoEditor(text: $input, placeholder: mode == .encode ? "输入要编码的文本" : "输入 Base64 字符串")
                .frame(height: 130)

            HStack {
                Toggle("URL 安全字母表 (-_)", isOn: $urlSafe)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WorkbenchTheme.textSecondary)
                Spacer()
                Button(mode == .encode ? "编码" : "解码") { compute() }
                    .buttonStyle(WorkbenchAccentButtonStyle(tint: CalcKind.base64.accent))
            }

            if !output.isEmpty {
                ResultBox(text: output)
            }
        }
        .onChange(of: input) { _, _ in compute() }
        .onChange(of: mode) { _, _ in compute() }
        .onChange(of: urlSafe) { _, _ in compute() }
    }

    /// 根据当前模式与参数重新计算输出。
    private func compute() {
        guard !input.isEmpty else { output = ""; return }
        if mode == .encode {
            var encoded = input.data(using: .utf8)?.base64EncodedString() ?? "（编码失败）"
            if urlSafe {
                encoded = encoded
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
            }
            output = encoded
        } else {
            var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if urlSafe {
                raw = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                while raw.count % 4 != 0 { raw.append("=") }
            }
            guard let data = Data(base64Encoded: raw, options: urlSafe ? [.ignoreUnknownCharacters] : []) else {
                output = "⚠️ 无法解码：不是合法的 Base64 字符串"
                return
            }
            output = String(data: data, encoding: .utf8) ?? "（非 UTF-8 文本数据，原始字节 \(data.count) 字节）"
        }
    }
}

// MARK: URL

/// URL 编码 / 解码工具。
private struct URLTool: View {
    /// 输入文本。
    @State private var input = ""
    /// 输出文本。
    @State private var output = ""
    /// 当前模式。
    @State private var mode: Mode = .encode

    /// 编码 / 解码模式。
    private enum Mode: String, CaseIterable, Identifiable {
        case encode, decode
        var id: String { rawValue }
        var title: String { self == .encode ? "编码" : "解码" }
    }

    var body: some View {
        CalcShell(accent: CalcKind.url.accent, eyebrow: "URL", title: "URL 百分号编解码") {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .padding(.bottom, 4)

            MonoEditor(text: $input, placeholder: mode == .encode ? "输入原始文本" : "输入待解码的 URL 片段")
                .frame(height: 130)

            Button(mode == .encode ? "编码" : "解码") { compute() }
                .buttonStyle(WorkbenchAccentButtonStyle(tint: CalcKind.url.accent))
                .frame(maxWidth: .infinity, alignment: .trailing)

            if !output.isEmpty {
                ResultBox(text: output)
            }
        }
        .onChange(of: input) { _, _ in compute() }
        .onChange(of: mode) { _, _ in compute() }
    }

    /// 重新计算 URL 编解码结果。
    private func compute() {
        guard !input.isEmpty else { output = ""; return }
        if mode == .encode {
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
            output = input.addingPercentEncoding(withAllowedCharacters: allowed) ?? "（编码失败）"
        } else {
            output = input.removingPercentEncoding ?? "（解码失败：包含非法转义）"
        }
    }
}

// MARK: Hash

/// 哈希摘要工具。
private struct HashTool: View {
    /// 输入文本。
    @State private var input = ""
    /// 输出文本。
    @State private var output = ""
    /// 所选算法。
    @State private var algorithm: HashAlg = .sha256
    /// 是否输出大写。
    @State private var uppercase = false

    /// 支持的哈希算法。
    private enum HashAlg: String, CaseIterable, Identifiable {
        case md5, sha1, sha256
        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
    }

    var body: some View {
        CalcShell(accent: CalcKind.hash.accent, eyebrow: "HASH", title: "哈希摘要 (MD5 / SHA1 / SHA256)") {
            HStack {
                Picker("算法", selection: $algorithm) {
                    ForEach(HashAlg.allCases) { a in
                        Text(a.title).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                Toggle("大写", isOn: $uppercase)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WorkbenchTheme.textSecondary)
            }

            MonoEditor(text: $input, placeholder: "输入待哈希的文本")
                .frame(height: 130)

            Button("计算哈希") { compute() }
                .buttonStyle(WorkbenchAccentButtonStyle(tint: CalcKind.hash.accent))
                .frame(maxWidth: .infinity, alignment: .trailing)

            if !output.isEmpty {
                ResultBox(text: output)
            }
        }
        .onChange(of: input) { _, _ in compute() }
        .onChange(of: algorithm) { _, _ in compute() }
        .onChange(of: uppercase) { _, _ in compute() }
    }

    /// 使用所选算法计算哈希。
    private func compute() {
        guard !input.isEmpty else { output = ""; return }
        guard let data = input.data(using: .utf8) else { output = "（编码失败）"; return }
        let digest = digest(for: algorithm, data: data)
        var text = digest.map { String(format: "%02x", $0) }.joined()
        if uppercase { text = text.uppercased() }
        output = text
    }

    /// 按算法返回原始字节摘要。
    private func digest(for alg: HashAlg, data: Data) -> [UInt8] {
        switch alg {
        case .md5:
            var d = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            data.withUnsafeBytes { buf in
                _ = CC_MD5(buf.baseAddress, CC_LONG(data.count), &d)
            }
            return d
        case .sha1:
            var d = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            data.withUnsafeBytes { buf in
                _ = CC_SHA1(buf.baseAddress, CC_LONG(data.count), &d)
            }
            return d
        case .sha256:
            var d = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            data.withUnsafeBytes { buf in
                _ = CC_SHA256(buf.baseAddress, CC_LONG(data.count), &d)
            }
            return d
        }
    }
}

// MARK: JWT

/// JWT 解析工具（仅解码，不校验签名）。
private struct JWTTool: View {
    /// 输入的 JWT 字符串。
    @State private var input = ""
    /// 头部解析结果。
    @State private var header = ""
    /// 载荷解析结果。
    @State private var payload = ""
    /// 错误信息。
    @State private var error: String?

    var body: some View {
        CalcShell(accent: CalcKind.jwt.accent, eyebrow: "JWT", title: "JWT 解码（不校验签名）") {
            MonoEditor(text: $input, placeholder: "粘贴 xxxxx.yyyyy.zzzzz 形式的 JWT", minHeight: 80)
                .frame(height: 90)

            Button("解析") { decode() }
                .buttonStyle(WorkbenchAccentButtonStyle(tint: CalcKind.jwt.accent))
                .frame(maxWidth: .infinity, alignment: .trailing)

            if let error {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WorkbenchTheme.coral)
                    .padding(.vertical, 4)
            } else if !header.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("HEADER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(WorkbenchTheme.textSecondary)
                    ResultBox(text: header)
                    Text("PAYLOAD")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(WorkbenchTheme.textSecondary)
                    ResultBox(text: payload)
                }
            }
        }
        .onChange(of: input) { _, _ in decode() }
    }

    /// 逐段解码 JWT 的 header 与 payload。
    private func decode() {
        header = ""
        payload = ""
        error = nil
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else {
            error = "⚠️ 格式不正确：JWT 应由三段以点分隔"
            return
        }
        guard let h = prettyJSON(from: parts[0]) else {
            error = "⚠️ 无法解码 Header 段"
            return
        }
        guard let p = prettyJSON(from: parts[1]) else {
            error = "⚠️ 无法解码 Payload 段"
            return
        }
        header = h
        payload = p
    }

    /// 将 Base64URL 段解码为格式化 JSON 文本。
    private func prettyJSON(from segment: String) -> String? {
        var raw = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while raw.count % 4 != 0 { raw.append("=") }
        guard let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let pretty = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }
}

// MARK: Timestamp

/// 时间戳 ↔ 日期互转工具。
private struct TimestampTool: View {
    /// 当前模式。
    @State private var mode: Mode = .toDate
    /// 待转换的时间戳文本。
    @State private var stamp = ""
    /// 转换后的日期展示。
    @State private var dateLines: [String] = []
    /// 反向转换所选日期。
    @State private var pickedDate = Date()

    /// 转换方向。
    private enum Mode: String, CaseIterable, Identifiable {
        case toDate, toStamp
        var id: String { rawValue }
        var title: String { self == .toDate ? "时间戳 → 日期" : "日期 → 时间戳" }
    }

    var body: some View {
        CalcShell(accent: CalcKind.timestamp.accent, eyebrow: "TIMESTAMP", title: "时间戳转换") {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            if mode == .toDate {
                MonoEditor(text: $stamp, placeholder: "输入秒级或毫秒级时间戳，如 1719200000", minHeight: 60)
                    .frame(height: 70)
                HStack {
                    Button("填入当前时间戳") {
                        stamp = String(Int(Date().timeIntervalSince1970))
                    }
                    .buttonStyle(WorkbenchAccentButtonStyle(tint: CalcKind.timestamp.accent))
                    Spacer()
                }
                if !dateLines.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(dateLines, id: \.self) { line in
                            HStack {
                                Text(line)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(WorkbenchTheme.textPrimary)
                                Spacer()
                                CopyButton(text: line.components(separatedBy: ": ").dropFirst().joined(separator: ": "))
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WorkbenchTheme.input)
                    .overlay {
                        RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                            .stroke(WorkbenchTheme.separator, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
                }
            } else {
                DatePicker("选择时间", selection: $pickedDate)
                    .datePickerStyle(.field)
                    .labelsHidden()
                let secs = Int(pickedDate.timeIntervalSince1970)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("秒级：\(secs)")
                            .font(.system(size: 12, design: .monospaced))
                        Spacer()
                        CopyButton(text: String(secs))
                    }
                    HStack {
                        Text("毫秒：\(secs * 1000)")
                            .font(.system(size: 12, design: .monospaced))
                        Spacer()
                        CopyButton(text: String(secs * 1000))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WorkbenchTheme.input)
                .overlay {
                    RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                        .stroke(WorkbenchTheme.separator, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
            }
        }
        .onChange(of: stamp) { _, _ in convert() }
        .onChange(of: mode) { _, _ in convert() }
    }

    /// 将时间戳转换为多种可读格式。
    private func convert() {
        dateLines = []
        guard let value = Double(stamp.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else { return }
        let seconds = value > 1_000_000_000_000 ? value / 1000 : value
        let date = Date(timeIntervalSince1970: seconds)
        let local = DateFormatter()
        local.dateStyle = .long
        local.timeStyle = .medium
        local.timeZone = .current
        let utc = DateFormatter()
        utc.dateStyle = .long
        utc.timeStyle = .medium
        utc.timeZone = TimeZone(identifier: "UTC")
        let iso = ISO8601DateFormatter().string(from: date)
        dateLines = [
            "本地时间: \(local.string(from: date))",
            "UTC 时间: \(utc.string(from: date))",
            "ISO 8601: \(iso)"
        ]
    }
}

// MARK: JSON

/// JSON 格式化 / 压缩 / 校验工具。
private struct JSONTool: View {
    /// 输入 JSON 文本。
    @State private var input = ""
    /// 输出文本。
    @State private var output = ""
    /// 错误信息。
    @State private var error: String?

    var body: some View {
        CalcShell(accent: CalcKind.json.accent, eyebrow: "JSON", title: "JSON 格式化 / 压缩") {
            MonoEditor(text: $input, placeholder: "粘贴 JSON 文本", minHeight: 140)
                .frame(height: 150)

            HStack {
                Button("格式化") { process(pretty: true) }
                    .buttonStyle(WorkbenchAccentButtonStyle(tint: CalcKind.json.accent))
                Button("压缩") { process(pretty: false) }
                    .buttonStyle(WorkbenchAccentButtonStyle(tint: WorkbenchTheme.textSecondary))
                Spacer()
                Button("校验") { validate() }
                    .buttonStyle(WorkbenchAccentButtonStyle(tint: WorkbenchTheme.neon))
            }

            if let error {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WorkbenchTheme.coral)
            } else if !output.isEmpty {
                ResultBox(text: output)
            }
        }
        .onChange(of: input) { _, _ in validate() }
    }

    /// 格式化或压缩 JSON。
    private func process(pretty: Bool) {
        error = nil
        guard !input.isEmpty else { output = ""; return }
        guard let data = input.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            error = "⚠️ 不是合法的 JSON"
            output = ""
            return
        }
        let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted] : []
        guard let result = try? JSONSerialization.data(withJSONObject: object, options: options),
              let text = String(data: result, encoding: .utf8) else {
            error = "⚠️ 序列化失败"
            return
        }
        output = text
    }

    /// 仅校验 JSON 合法性。
    private func validate() {
        error = nil
        guard !input.isEmpty else { output = ""; return }
        guard let data = input.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            error = "⚠️ 不是合法的 JSON"
            return
        }
        output = "✓ JSON 格式合法"
    }
}

// MARK: Unit

/// 单位换算工具（字节与进制）。
private struct UnitTool: View {
    /// 待转换的数值文本。
    @State private var value = ""
    /// 当前字节单位。
    @State private var byteUnit: ByteUnit = .mb
    /// 当前进制。
    @State private var base: Base = .dec
    /// 进制输入文本。
    @State private var baseValue = ""

    /// 字节单位。
    private enum ByteUnit: String, CaseIterable, Identifiable {
        case b, kb, mb, gb, tb
        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
        var factor: Double {
            switch self {
            case .b: 1
            case .kb: 1024
            case .mb: 1024 * 1024
            case .gb: 1024 * 1024 * 1024
            case .tb: 1024 * 1024 * 1024 * 1024
            }
        }
    }

    /// 数制。
    private enum Base: String, CaseIterable, Identifiable {
        case dec, hex, bin
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dec: "十进制"
            case .hex: "十六进制"
            case .bin: "二进制"
            }
        }
    }

    var body: some View {
        CalcShell(accent: CalcKind.unit.accent, eyebrow: "UNIT", title: "单位换算") {
            // 字节换算
            Text("字节容量")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WorkbenchTheme.textSecondary)
            HStack {
                TextField("数值", text: $value)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(10)
                    .background(WorkbenchTheme.input)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(WorkbenchTheme.separator, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Picker("单位", selection: $byteUnit) {
                    ForEach(ByteUnit.allCases) { u in
                        Text(u.title).tag(u)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 90)
            }

            let bytes = (Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) * byteUnit.factor
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(ByteUnit.allCases) { u in
                    HStack {
                        Text(u.title)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(WorkbenchTheme.textTertiary)
                            .frame(width: 34, alignment: .leading)
                        Spacer()
                        Text(format(bytes / u.factor))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(WorkbenchTheme.textPrimary)
                    }
                    .padding(10)
                    .background(WorkbenchTheme.input)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(WorkbenchTheme.separator, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

            Divider().padding(.vertical, 6)

            // 进制换算
            Text("进制转换")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WorkbenchTheme.textSecondary)
            HStack {
                Picker("输入进制", selection: $base) {
                    ForEach(Base.allCases) { b in
                        Text(b.title).tag(b)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                TextField("数值", text: $baseValue)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(10)
                    .background(WorkbenchTheme.input)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(WorkbenchTheme.separator, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            if let converted = convertBase() {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                    baseRow("十进制", converted.dec)
                    baseRow("十六进制", converted.hex)
                    baseRow("二进制", converted.bin)
                }
            }
        }
        .onChange(of: value) { _, _ in }
        .onChange(of: baseValue) { _, _ in }
    }

    /// 将字节数格式化为紧凑可读文本。
    private func format(_ n: Double) -> String {
        if n.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", n)
        }
        return String(format: "%.2f", n)
    }

    /// 按所选输入进制解析并转换为三种进制展示。
    private func convertBase() -> (dec: String, hex: String, bin: String)? {
        let raw = baseValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let number: UInt64?
        switch base {
        case .dec: number = UInt64(raw)
        case .hex: number = UInt64(raw, radix: 16)
        case .bin: number = UInt64(raw, radix: 2)
        }
        guard let n = number else { return nil }
        return (String(n), "0x" + String(n, radix: 16).uppercased(), "0b" + String(n, radix: 2))
    }

    /// 单进制结果行。
    private func baseRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.textTertiary)
                .frame(width: 64, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.textPrimary)
        }
        .padding(10)
        .background(WorkbenchTheme.input)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(WorkbenchTheme.separator, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
