import SwiftUI
import Charts
import Darwin

/// 单次 CPU 使用率快照。
struct CPUSnapshot: Sendable {
    /// 全部核心的综合使用率，范围为 0...100。
    let overall: Double
    /// 每个逻辑核心的使用率，范围为 0...100。
    let perCore: [Double]
}

/// 单次物理内存使用快照。
struct MemSnapshot: Sendable {
    /// 物理内存总字节数。
    let total: UInt64
    /// 估算的已用内存字节数。
    let used: UInt64
    /// 可回收与空闲内存字节数。
    let available: UInt64
    /// 联动内存字节数。
    let wired: UInt64
    /// 活跃内存字节数。
    let active: UInt64
    /// 压缩内存字节数。
    let compressed: UInt64
}

/// 系统磁盘容量快照。
struct DiskSnapshot: Sendable {
    /// 根卷总字节数。
    let total: UInt64
    /// 根卷可用字节数。
    let available: UInt64

    /// 根卷已用字节数。
    var used: UInt64 { total > available ? total - available : 0 }
}

/// `ps` 返回的一条运行中进程记录。
struct RunningProcess: Sendable, Identifiable, Hashable {
    /// 进程标识，同时作为表格稳定身份。
    let pid: Int
    /// 可执行文件或进程名称。
    let name: String
    /// CPU 使用率百分比。
    let cpu: Double
    /// 物理内存占比百分比。
    let memory: Double
    /// 进程所属用户。
    let user: String

    /// SwiftUI 列表使用的稳定标识。
    var id: Int { pid }
}

/// 用于趋势图的一次资源采样。
struct ResourceSample: Sendable, Identifiable {
    /// 采样时间，同时作为趋势点标识。
    let date: Date
    /// CPU 综合使用率。
    let cpu: Double
    /// 内存使用率。
    let memory: Double

    /// SwiftUI 图表使用的稳定标识。
    var id: Date { date }
}

/// 采样并发布 macOS 实时资源状态。
@MainActor
final class SystemMonitor: ObservableObject {
    /// CPU 综合使用率。
    @Published var cpuOverall: Double = 0
    /// 每个逻辑核心的 CPU 使用率。
    @Published var cpuPerCore: [Double] = []
    /// 最近一次内存快照。
    @Published var mem: MemSnapshot?
    /// 最近一次磁盘快照。
    @Published var disk: DiskSnapshot?
    /// 按 CPU 排序的高占用进程。
    @Published var topProcesses: [RunningProcess] = []
    /// PID 精确查询结果。
    @Published var pidResult: RunningProcess?
    /// PID 查询的状态说明。
    @Published var pidMessage: String?
    /// 最近 60 次 CPU 与内存采样。
    @Published var history: [ResourceSample] = []
    /// 是否暂停自动刷新。
    @Published var isPaused = false
    /// 当前是否正在后台刷新。
    @Published var isRefreshing = false
    /// 当前是否正在查询指定 PID。
    @Published var isLookingUpPID = false
    /// 最近一次成功刷新时间。
    @Published var lastUpdated: Date?
    /// 最近一次采样错误。
    @Published var errorMessage: String?
    /// 自动刷新间隔秒数。
    @Published var refreshInterval: TimeInterval = 2

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var lookupTask: Task<Void, Never>?
    private var previousCPU: [(user: Double, system: Double, nice: Double, idle: Double)] = []

    /// 开始系统资源自动采样。
    func start() {
        guard timer == nil else { return }
        refresh()
        scheduleTimer()
    }

    /// 停止自动采样并取消尚未完成的后台任务。
    func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        lookupTask?.cancel()
        isRefreshing = false
        isLookingUpPID = false
    }

    /// 手动触发一次完整资源采样。
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        // 原生 Mach 采样耗时极短，并且 CPU delta 状态需要串行更新。
        let cpu = sampleCPU()
        let memory = sampleMemory()
        cpuOverall = cpu.overall
        cpuPerCore = cpu.perCore
        mem = memory

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                let processes = Shell.run(
                    executable: "/bin/ps",
                    arguments: ["-A", "-o", "pid=,pcpu=,pmem=,user=,comm=", "-r"],
                    outputLimit: 400_000
                )
                let disk = Self.sampleDisk()
                return (processes, disk)
            }.value
            guard let self, !Task.isCancelled else { return }

            let parsed = self.parseProcesses(result.0.output)
            self.topProcesses = Array(parsed.prefix(40))
            self.disk = result.1
            self.lastUpdated = Date()
            self.errorMessage = result.0.exitCode == 0 ? nil : "进程列表读取失败：\(result.0.error)"
            self.appendHistory(cpu: cpu.overall, memory: self.memoryUsagePercent)
            self.isRefreshing = false
        }
    }

    /// 切换自动刷新暂停状态；恢复时立即采样。
    func togglePaused() {
        isPaused.toggle()
        if !isPaused { refresh() }
    }

    /// 更新自动刷新间隔并重建计时器。
    /// - Parameter interval: 新的刷新间隔秒数。
    func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        scheduleTimer()
        if !isPaused { refresh() }
    }

    /// 在后台查询指定 PID 的实时资源信息。
    /// - Parameter pid: 大于零的进程标识。
    func lookup(pid: Int) {
        guard pid > 0 else {
            pidResult = nil
            pidMessage = "请输入有效的正整数 PID。"
            return
        }
        isLookingUpPID = true
        pidMessage = nil
        lookupTask?.cancel()
        lookupTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Shell.run(
                    executable: "/bin/ps",
                    arguments: ["-o", "pid=,pcpu=,pmem=,user=,comm=", "-p", "\(pid)"],
                    outputLimit: 20_000
                )
            }.value
            guard let self, !Task.isCancelled else { return }
            let process = self.parseProcesses(result.output).first
            self.pidResult = process
            self.pidMessage = process == nil ? "未找到 PID \(pid)，进程可能已退出或权限不足。" : nil
            self.isLookingUpPID = false
        }
    }

    /// 当前内存使用率，范围为 0...100。
    var memoryUsagePercent: Double {
        guard let mem, mem.total > 0 else { return 0 }
        return min(max(Double(mem.used) / Double(mem.total) * 100, 0), 100)
    }

    /// 当前根卷磁盘使用率，范围为 0...100。
    var diskUsagePercent: Double {
        guard let disk, disk.total > 0 else { return 0 }
        return min(max(Double(disk.used) / Double(disk.total) * 100, 0), 100)
    }

    /// 系统本次启动后的运行时长说明。
    var uptimeDescription: String {
        let seconds = Foundation.ProcessInfo.processInfo.systemUptime
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        if days > 0 { return "\(days)天 \(hours)小时" }
        let minutes = (Int(seconds) % 3_600) / 60
        return "\(hours)小时 \(minutes)分"
    }

    /// 按当前间隔创建自动刷新计时器。
    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPaused else { return }
                self.refresh()
            }
        }
    }

    /// 通过 Mach host API 采集各核心 CPU delta。
    /// - Returns: 综合与逐核心 CPU 使用率。
    private func sampleCPU() -> CPUSnapshot {
        var numberOfCPUs: natural_t = 0
        var cpuInfo: UnsafeMutablePointer<Int32>?
        var cpuInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numberOfCPUs,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else {
            return CPUSnapshot(overall: 0, perCore: [])
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(Int(bitPattern: cpuInfo)),
                vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<Int32>.size)
            )
        }

        var cores: [Double] = []
        var overallUsed = 0.0
        var overallIdle = 0.0
        var nextPrevious: [(Double, Double, Double, Double)] = []

        for index in 0..<Int(numberOfCPUs) {
            let offset = index * Int(CPU_STATE_MAX)
            let user = Double(cpuInfo[offset + Int(CPU_STATE_USER)])
            let system = Double(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            let nice = Double(cpuInfo[offset + Int(CPU_STATE_NICE)])
            let idle = Double(cpuInfo[offset + Int(CPU_STATE_IDLE)])

            if index < previousCPU.count {
                let prior = previousCPU[index]
                let deltaUser = max(user - prior.user, 0)
                let deltaSystem = max(system - prior.system, 0)
                let deltaNice = max(nice - prior.nice, 0)
                let deltaIdle = max(idle - prior.idle, 0)
                let deltaUsed = deltaUser + deltaSystem + deltaNice
                let deltaTotal = deltaUsed + deltaIdle
                cores.append(deltaTotal > 0 ? deltaUsed / deltaTotal * 100 : 0)
                overallUsed += deltaUsed
                overallIdle += deltaIdle
            } else {
                cores.append(0)
            }
            nextPrevious.append((user, system, nice, idle))
        }
        previousCPU = nextPrevious
        let total = overallUsed + overallIdle
        return CPUSnapshot(overall: total > 0 ? overallUsed / total * 100 : 0, perCore: cores)
    }

    /// 通过 Mach VM API 采集物理内存使用明细。
    /// - Returns: 当前内存快照。
    private func sampleMemory() -> MemSnapshot {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let bytesPerPage = UInt64(pageSize)
        let active = UInt64(statistics.active_count) * bytesPerPage
        let wired = UInt64(statistics.wire_count) * bytesPerPage
        let compressed = UInt64(statistics.compressor_page_count) * bytesPerPage
        let total = physicalMemoryBytes()
        // 活跃、联动与压缩内存更接近 Activity Monitor 的“已用内存”口径。
        let used = min(active + wired + compressed, total)
        return MemSnapshot(
            total: total,
            used: used,
            available: total - used,
            wired: wired,
            active: active,
            compressed: compressed
        )
    }

    /// 读取本机物理内存总量。
    /// - Returns: 物理内存总字节数。
    private func physicalMemoryBytes() -> UInt64 {
        var size: UInt64 = 0
        var length = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &length, nil, 0)
        return size
    }

    /// 读取根卷总容量与可用容量。
    /// - Returns: 当前磁盘快照；读取失败时返回 nil。
    nonisolated private static func sampleDisk() -> DiskSnapshot? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let totalNumber = attributes[.systemSize] as? NSNumber,
              let freeNumber = attributes[.systemFreeSize] as? NSNumber else { return nil }
        return DiskSnapshot(total: totalNumber.uint64Value, available: freeNumber.uint64Value)
    }

    /// 解析 `ps` 的 pid/cpu/mem/user/comm 五列输出。
    /// - Parameter text: `ps` 标准输出。
    /// - Returns: 可用于展示的进程记录。
    private func parseProcesses(_ text: String) -> [RunningProcess] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            // 限制为五段，确保命令名中包含空格时仍被完整保留。
            let parts = line.split(maxSplits: 4, whereSeparator: \.isWhitespace)
            guard parts.count == 5,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let memory = Double(parts[2]) else { return nil }
            return RunningProcess(
                pid: pid,
                name: String(parts[4]),
                cpu: cpu,
                memory: memory,
                user: String(parts[3])
            )
        }
    }

    /// 追加趋势采样，并限制历史窗口为 60 个点。
    /// - Parameters:
    ///   - cpu: CPU 综合使用率。
    ///   - memory: 内存使用率。
    private func appendHistory(cpu: Double, memory: Double) {
        history.append(ResourceSample(date: Date(), cpu: cpu, memory: memory))
        if history.count > 60 {
            history.removeFirst(history.count - 60)
        }
    }
}

/// 实时系统资源监控界面。
struct MonitorView: View {
    /// 根视图共享的系统监控模型。
    @ObservedObject var monitor: SystemMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pidInput = ""
    @State private var processFilter = ""
    @State private var selectedProcessID: RunningProcess.ID?

    private let lime = WorkbenchTheme.neon
    private let cyan = WorkbenchTheme.cyan
    private let coral = WorkbenchTheme.coral

    private var filteredProcesses: [RunningProcess] {
        guard !processFilter.isEmpty else { return monitor.topProcesses }
        return monitor.topProcesses.filter {
            $0.name.localizedCaseInsensitiveContains(processFilter) ||
            $0.user.localizedCaseInsensitiveContains(processFilter) ||
            String($0.pid).contains(processFilter)
        }
    }

    private var selectedProcess: RunningProcess? {
        guard let selectedProcessID else { return nil }
        return monitor.topProcesses.first { $0.id == selectedProcessID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusStrip
                    metricGrid
                    coreSection
                    processSection
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WorkbenchTheme.canvas)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: monitor.history.count)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(monitor.isPaused ? coral : lime)
                        .frame(width: 7, height: 7)
                    Text(monitor.isPaused ? "PAUSED / 03" : "LIVE / 03")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(monitor.isPaused ? coral : lime)
                }
                Text("系统脉搏")
                    .font(.system(size: 30, weight: .bold))
                Text("读懂机器此刻的负载，而不是只看一个孤立数字。")
                    .font(.callout)
                    .foregroundStyle(WorkbenchTheme.overlay(0.52))
            }
            Spacer()
            HStack(spacing: 8) {
                Menu {
                    ForEach([1.0, 2.0, 5.0, 10.0], id: \.self) { interval in
                        Button {
                            monitor.setRefreshInterval(interval)
                        } label: {
                            if monitor.refreshInterval == interval {
                                Label("\(Int(interval)) 秒", systemImage: "checkmark")
                            } else {
                                Text("\(Int(interval)) 秒")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "timer")
                        .frame(width: 32, height: 32)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("刷新间隔：\(Int(monitor.refreshInterval)) 秒")

                Button { monitor.togglePaused() } label: {
                    Image(systemName: monitor.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .background(WorkbenchTheme.overlay(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .help(monitor.isPaused ? "继续自动刷新" : "暂停自动刷新")

                Button { monitor.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(monitor.isRefreshing && !reduceMotion ? 180 : 0))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: monitor.isRefreshing)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .background(lime)
                .foregroundStyle(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(monitor.isRefreshing)
                .help("立即刷新")
            }
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 0) {
            statusCell(label: "UPTIME", value: monitor.uptimeDescription, color: lime)
            stripDivider
            statusCell(label: "CORES", value: "\(monitor.cpuPerCore.count)", color: cyan)
            stripDivider
            statusCell(label: "DISK", value: String(format: "%.0f%%", monitor.diskUsagePercent), color: coral)
            stripDivider
            statusCell(
                label: "UPDATED",
                value: monitor.lastUpdated?.formatted(date: .omitted, time: .standard) ?? "--:--:--",
                color: .white
            )
        }
        .padding(.vertical, 12)
        .background(WorkbenchTheme.overlay(0.035))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(WorkbenchTheme.overlay(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(WorkbenchTheme.overlay(0.08))
            .frame(width: 1, height: 34)
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
            ResourceMetricPanel(
                eyebrow: "PROCESSOR",
                value: String(format: "%4.1f", monitor.cpuOverall),
                unit: "%",
                detail: "整体 CPU 使用率",
                color: cyan,
                history: monitor.history,
                valuePath: \.cpu
            )
            ResourceMetricPanel(
                eyebrow: "MEMORY",
                value: String(format: "%4.1f", monitor.memoryUsagePercent),
                unit: "%",
                detail: memoryDetail,
                color: coral,
                history: monitor.history,
                valuePath: \.memory
            )
        }
    }

    private var memoryDetail: String {
        guard let memory = monitor.mem else { return "正在读取物理内存" }
        return "\(formatBytes(memory.used)) / \(formatBytes(memory.total))"
    }

    private var coreSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(index: "01", title: "核心热区", detail: "逻辑核心的即时负载")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
                ForEach(Array(monitor.cpuPerCore.enumerated()), id: \.offset) { index, usage in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(String(format: "%02d", index))
                            Spacer()
                            Text(String(format: "%.0f", usage))
                        }
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(WorkbenchTheme.overlay(0.07))
                                Rectangle()
                                    .fill(coreColor(for: usage))
                                    .frame(width: geometry.size.width * CGFloat(min(max(usage, 0), 100)) / 100)
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(10)
                    .background(WorkbenchTheme.overlay(0.045))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(WorkbenchTheme.overlay(0.06)))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(index: "02", title: "进程雷达", detail: "按 CPU 使用率实时排序")
            HStack(spacing: 10) {
                searchField
                pidLookup
            }
            Table(filteredProcesses, selection: $selectedProcessID) {
                TableColumn("PID") { process in
                    Text("\(process.pid)")
                        .font(.system(.callout, design: .monospaced))
                        .contextMenu { Button("复制 PID") { copyToPasteboard("\(process.pid)") } }
                }
                .width(min: 58, ideal: 72, max: 90)
                TableColumn("进程") { process in
                    Text(process.name)
                        .lineLimit(1)
                        .help(process.name)
                        .contextMenu {
                            Button("复制名称") { copyToPasteboard(process.name) }
                            Button("复制 PID") { copyToPasteboard("\(process.pid)") }
                        }
                }
                TableColumn("用户") { Text($0.user).lineLimit(1) }
                    .width(min: 80, ideal: 110)
                TableColumn("CPU %") {
                    Text(String(format: "%6.1f", $0.cpu))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle($0.cpu > 50 ? coral : .primary)
                }
                .width(72)
                TableColumn("MEM %") {
                    Text(String(format: "%5.1f", $0.memory))
                        .font(.system(.callout, design: .monospaced))
                }
                .width(72)
            }
            .frame(minHeight: 250, idealHeight: 290)
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 7))

            if let process = monitor.pidResult ?? selectedProcess {
                processInspector(process)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let message = monitor.pidMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(coral)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(WorkbenchTheme.overlay(0.36))
            TextField("筛选进程、用户或 PID", text: $processFilter)
                .textFieldStyle(.plain)
            if !processFilter.isEmpty {
                Button { processFilter = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(WorkbenchTheme.overlay(0.36))
                    .help("清除筛选")
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(WorkbenchTheme.overlay(0.055))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(WorkbenchTheme.overlay(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var pidLookup: some View {
        HStack(spacing: 7) {
            Text("PID")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(cyan)
            TextField("1234", text: $pidInput)
                .textFieldStyle(.plain)
                .frame(width: 72)
                .onSubmit(lookupPID)
            Button(action: lookupPID) {
                if monitor.isLookingUpPID {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .background(cyan)
            .foregroundStyle(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .disabled(Int(pidInput) == nil || monitor.isLookingUpPID)
            .help("查询 PID")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 34)
        .background(WorkbenchTheme.overlay(0.055))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(WorkbenchTheme.overlay(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// 创建状态条中的单个指标单元。
    /// - Parameters:
    ///   - label: 指标英文标签。
    ///   - value: 指标值。
    ///   - color: 值的语义颜色。
    /// - Returns: 等宽状态单元。
    private func statusCell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.overlay(0.34))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 创建带编号的监控区块标题。
    /// - Parameters:
    ///   - index: 区块编号。
    ///   - title: 区块标题。
    ///   - detail: 区块补充说明。
    /// - Returns: 统一区块标题。
    private func sectionHeading(index: String, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(index)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(lime)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(WorkbenchTheme.overlay(0.38))
            Spacer()
        }
    }

    /// 根据核心负载返回分级语义颜色。
    /// - Parameter usage: CPU 使用率。
    /// - Returns: 低、中、高负载颜色。
    private func coreColor(for usage: Double) -> Color {
        if usage >= 75 { return coral }
        if usage >= 40 { return lime }
        return cyan
    }

    /// 创建选中或查询进程的紧凑检查器。
    /// - Parameter process: 要展示的进程。
    /// - Returns: 进程详情栏。
    private func processInspector(_ process: RunningProcess) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SELECTED PROCESS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(lime)
                Text(process.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer()
            inspectorValue(label: "PID", value: "\(process.pid)")
            inspectorValue(label: "USER", value: process.user)
            inspectorValue(label: "CPU", value: String(format: "%.1f%%", process.cpu))
            inspectorValue(label: "MEM", value: String(format: "%.1f%%", process.memory))
            Button { copyToPasteboard("\(process.pid)") } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .background(WorkbenchTheme.overlay(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .help("复制 PID")
        }
        .padding(12)
        .background(WorkbenchTheme.overlay(0.045))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(WorkbenchTheme.overlay(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    /// 创建进程检查器中的标签值。
    /// - Parameters:
    ///   - label: 字段标签。
    ///   - value: 字段值。
    /// - Returns: 垂直排列的标签值。
    private func inspectorValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.overlay(0.34))
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
    }

    /// 执行 PID 输入框中的查询。
    private func lookupPID() {
        guard let pid = Int(pidInput), pid > 0 else { return }
        monitor.lookup(pid: pid)
    }

    /// 将字节数格式化为适合资源监控的短文本。
    /// - Parameter bytes: 原始字节数。
    /// - Returns: GB 或 MB 文本。
    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

/// 包含大数字与趋势线的资源指标面板。
private struct ResourceMetricPanel: View {
    /// 面板英文标签。
    let eyebrow: String
    /// 指标主数值。
    let value: String
    /// 指标单位。
    let unit: String
    /// 指标补充说明。
    let detail: String
    /// 指标语义色。
    let color: Color
    /// 趋势采样数据。
    let history: [ResourceSample]
    /// 从采样中读取指标值的路径。
    let valuePath: KeyPath<ResourceSample, Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.overlay(0.4))
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 38, weight: .black, design: .monospaced))
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
            Chart(history) { sample in
                AreaMark(
                    x: .value("时间", sample.date),
                    y: .value("使用率", sample[keyPath: valuePath])
                )
                .foregroundStyle(color.opacity(0.12))
                .interpolationMethod(.catmullRom)
                LineMark(
                    x: .value("时间", sample.date),
                    y: .value("使用率", sample[keyPath: valuePath])
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 70)
        }
        .padding(16)
        .background(WorkbenchTheme.overlay(0.045))
        .overlay(alignment: .topLeading) {
            Rectangle().fill(color).frame(width: 46, height: 2)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WorkbenchTheme.overlay(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
