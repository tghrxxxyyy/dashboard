import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 端口与进程管家：列出监听端口、对应 App 与一键清理。
struct PortPilotView: View {
    /// 端口数据来源。
    @StateObject private var store = PortPilotStore()
    /// 搜索过滤文本。
    @State private var query = ""
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 过滤后的端口条目。
    private var filtered: [PortPilotStore.Entry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.appName.lowercased().contains(q)
                || $0.command.lowercased().contains(q)
                || String($0.port).contains(q)
                || $0.address.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerRow

                if store.entries.isEmpty {
                    WorkbenchEmptyState(
                        systemImage: "network",
                        title: store.lastError == nil ? "暂未发现监听端口" : "端口读取失败",
                        detail: store.lastError ?? "稍后自动刷新，或点击右上角手动刷新"
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    serviceOverview
                    portList
                }
            }
            .padding(WorkbenchTheme.pagePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.start() }
        .onDisappear { store.stop() }
    }

    /// 顶部标题、搜索与刷新控制。
    private var headerRow: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                Rectangle()
                    .fill(WorkbenchTheme.violet)
                    .frame(width: 3, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("PORT PILOT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(WorkbenchTheme.violet)
                    Text("端口与进程管家")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(WorkbenchTheme.textPrimary)
                }

                Spacer(minLength: 16)

                HStack(spacing: 10) {
                    Toggle("自动刷新", isOn: $store.autoRefresh)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WorkbenchTheme.textSecondary)
                    Button {
                        store.refresh()
                    } label: {
                        Image(systemName: store.isRefreshing ? "arrow.clockwise" : "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WorkbenchTheme.violet)
                            .frame(width: 34, height: 32)
                            .background(WorkbenchTheme.panel)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(WorkbenchTheme.separator, lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .rotationEffect(.degrees(store.isRefreshing ? 180 : 0))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: store.isRefreshing)
                    }
                    .buttonStyle(.plain)
                    .help("刷新端口列表")
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WorkbenchTheme.textTertiary)
                TextField("按端口 / 应用 / 地址过滤", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(WorkbenchTheme.textPrimary)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(WorkbenchTheme.input)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(WorkbenchTheme.separator, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// 按 App 聚合的服务总览卡片。
    private var serviceOverview: some View {
        let grouped = Dictionary(grouping: store.entries, by: { $0.appName })
        let cards = grouped.map { (name: $0.key, entries: $0.value, icon: $0.value.first?.icon) }
            .sorted { $0.entries.count > $1.entries.count }

        return VStack(alignment: .leading, spacing: 12) {
            WorkbenchSectionHeader(eyebrow: "SERVICES", title: "服务总览", trailing: "\(cards.count) 个应用", accent: WorkbenchTheme.violet)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(cards, id: \.name) { card in
                    HStack(spacing: 12) {
                        if let icon = card.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        } else {
                            Image(systemName: "app.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(WorkbenchTheme.textTertiary)
                                .frame(width: 34, height: 34)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(card.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WorkbenchTheme.textPrimary)
                                .lineLimit(1)
                            Text(card.entries.map { String($0.port) }.joined(separator: ", "))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(WorkbenchTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text("\(card.entries.count)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(WorkbenchTheme.violet)
                    }
                    .padding(14)
                    .background(WorkbenchTheme.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                            .stroke(WorkbenchTheme.separator, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
                }
            }
        }
    }

    /// 端口明细列表。
    private var portList: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkbenchSectionHeader(
                eyebrow: "LISTENERS",
                title: "监听端口",
                trailing: "\(filtered.count) / \(store.entries.count)",
                accent: WorkbenchTheme.violet
            )

            VStack(spacing: 8) {
                ForEach(filtered) { entry in
                    PortRow(entry: entry) {
                        store.kill(entry)
                    } copyPID: {
                        copyToPasteboard(String(entry.pid))
                    }
                }
            }
        }
    }
}

/// 单个监听端口行。
private struct PortRow: View {
    /// 端口条目。
    let entry: PortPilotStore.Entry
    /// 结束进程回调。
    let onKill: () -> Void
    /// 复制 PID 回调。
    let copyPID: () -> Void

    /// 当前指针是否悬停。
    @State private var isHovered = false
    /// 系统是否要求减少动态效果。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            if let icon = entry.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(WorkbenchTheme.textTertiary)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(entry.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WorkbenchTheme.textPrimary)
                    if entry.isConflicting {
                        Text("冲突")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(WorkbenchTheme.coral)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WorkbenchTheme.coral.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
                Text("\(entry.command) · PID \(entry.pid) · \(entry.user)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                Text(":\(entry.port)")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.textPrimary)
                Text("\(entry.proto) · \(entry.address)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.textTertiary)
            }

            HStack(spacing: 6) {
                Button { copyPID() } label: {
                    Image(systemName: "number")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WorkbenchTheme.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("复制 PID")

                Button { onKill() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isHovered ? WorkbenchTheme.coral : WorkbenchTheme.textTertiary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("结束该进程")
            }
        }
        .padding(12)
        .background(isHovered ? WorkbenchTheme.panelRaised : WorkbenchTheme.panel)
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                .stroke(isHovered ? WorkbenchTheme.violet.opacity(0.3) : WorkbenchTheme.separator, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : WorkbenchTheme.motionQuick) {
                isHovered = hovered
            }
        }
    }
}

/// 端口与进程管家数据来源：解析 lsof 并解析 App 图标。
@MainActor
final class PortPilotStore: ObservableObject {
    /// 单个监听端口条目。
    struct Entry: Identifiable {
        /// 稳定标识。
        let id = UUID()
        /// 端口号。
        let port: Int
        /// 协议（TCP / UDP）。
        let proto: String
        /// 监听地址。
        let address: String
        /// 进程 PID。
        let pid: Int
        /// 命令名。
        let command: String
        /// 所属用户。
        let user: String
        /// 解析出的 App 名称。
        let appName: String
        /// App 图标（可能为 nil）。
        let icon: NSImage?
        /// 是否存在端口冲突。
        let isConflicting: Bool
    }

    /// 当前端口条目列表。
    @Published var entries: [Entry] = []
    /// 最近一次错误信息。
    @Published var lastError: String?
    /// 是否正在刷新。
    @Published var isRefreshing = false
    /// 是否自动刷新。
    @Published var autoRefresh = true

    /// 刷新定时器。
    private var timer: Timer?

    /// 启动自动刷新。
    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self?.autoRefresh == true else { return }
                self?.refresh()
            }
        }
    }

    /// 停止自动刷新。
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 立即刷新端口列表。
    func refresh() {
        isRefreshing = true
        Task.detached(priority: .userInitiated) {
            let tcp = Shell.run("lsof -nP -iTCP -sTCP:LISTEN -l 2>/dev/null", outputLimit: 2_000_000)
            let udp = Shell.run("lsof -nP -iUDP -l 2>/dev/null", outputLimit: 2_000_000)
            let raw = Self.parse(tcp.output, proto: "TCP") + Self.parse(udp.output, proto: "UDP")
            await MainActor.run {
                self.resolveAndPublish(raw)
                self.isRefreshing = false
                if tcp.exitCode != 0 && udp.exitCode != 0 {
                    self.lastError = "无法执行 lsof，请确认系统完整性。"
                } else {
                    self.lastError = nil
                }
            }
        }
    }

    /// 结束指定端口对应的进程。
    /// - Parameter entry: 需要结束的端口条目。
    func kill(_ entry: Entry) {
        let result = Shell.run("kill -9 \(entry.pid) 2>/dev/null || sudo -n kill -9 \(entry.pid) 2>/dev/null")
        if result.exitCode != 0 {
            lastError = "结束 PID \(entry.pid) 失败：可能需要手动授权（sudo）。"
        } else {
            lastError = nil
        }
        refresh()
    }

    /// 在主线程解析图标并发布条目（NSRunningApplication 需主线程）。
    private func resolveAndPublish(_ raw: [RawPort]) {
        // 端口冲突检测
        var counts: [String: Int] = [:]
        for r in raw {
            counts["\(r.proto):\(r.port)", default: 0] += 1
        }
        let resolved: [Entry] = raw.map { r in
            let app = NSRunningApplication(processIdentifier: pid_t(r.pid))
            let icon = app?.icon
                ?? NSWorkspace.shared.icon(for: .executable)
            let name = app?.localizedName ?? r.command
            let conflict = (counts["\(r.proto):\(r.port)"] ?? 0) > 1
            return Entry(
                port: r.port,
                proto: r.proto,
                address: r.address,
                pid: r.pid,
                command: r.command,
                user: r.user,
                appName: name,
                icon: icon,
                isConflicting: conflict
            )
        }
        entries = resolved.sorted { $0.port < $1.port }
    }

    /// 解析 lsof 纯文本输出。
    private nonisolated static func parse(_ text: String, proto: String) -> [RawPort] {
        var out: [RawPort] = []
        for line in text.split(separator: "\n") {
            let s = String(line)
            guard !s.hasPrefix("COMMAND") else { continue }
            let parts = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 9, let pid = Int(parts[1]) else { continue }
            let command = parts[0]
            let user = parts[2]
            let nameField = parts.last ?? ""
            guard let range = nameField.range(of: #":(\d+)"#, options: .regularExpression),
                  let port = Int(nameField[range].dropFirst()) else { continue }
            let address = String(nameField[..<range.lowerBound])
            out.append(RawPort(port: port, proto: proto, address: address, pid: pid, command: command, user: user))
        }
        return out
    }
}

/// lsof 解析出的原始端口记录（未包含图标）。
private struct RawPort {
    /// 端口号。
    let port: Int
    /// 协议。
    let proto: String
    /// 监听地址。
    let address: String
    /// 进程 PID。
    let pid: Int
    /// 命令名。
    let command: String
    /// 所属用户。
    let user: String
}
