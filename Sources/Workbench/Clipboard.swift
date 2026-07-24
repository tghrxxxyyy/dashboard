import SwiftUI
import AppKit

/// 剪贴板历史：轮询系统剪贴板，记录最近复制的文本与文件。
struct ClipboardView: View {
    /// 剪贴板数据来源。
    @StateObject private var store = ClipboardStore()
    /// 搜索过滤文本。
    @State private var query = ""
    /// 类型过滤。
    @State private var filter: Filter = .all

    /// 类型过滤模式。
    private enum Filter: String, CaseIterable, Identifiable {
        case all, text, file
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "全部"
            case .text: "文本"
            case .file: "文件"
            }
        }
    }

    /// 过滤后的条目。
    private var filtered: [ClipboardStore.Entry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.entries.filter { entry in
            let matches: Bool = {
                switch filter {
                case .all: return true
                case .text: return entry.kind == .text
                case .file: return entry.kind == .file
                }
            }()
            guard matches else { return false }
            if q.isEmpty { return true }
            return entry.preview.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            Divider()

            if filtered.isEmpty {
                WorkbenchEmptyState(
                    systemImage: "doc.on.clipboard",
                    title: store.isMonitoring ? "还没有记录" : "监听已暂停",
                    detail: store.isMonitoring ? "复制点什么，这里就会出现历史" : "点击右上角继续监听系统剪贴板"
                )
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { entry in
                            ClipboardRow(entry: entry) {
                                store.apply(entry)
                            } onPin: {
                                store.togglePin(entry)
                            } onRemove: {
                                store.remove(entry)
                            }
                        }
                    }
                    .padding(WorkbenchTheme.pagePadding)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.start() }
        .onDisappear { store.stop() }
    }

    /// 顶部标题、过滤与监听控制。
    private var headerRow: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                Rectangle()
                    .fill(WorkbenchTheme.violet)
                    .frame(width: 3, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CLIPBOARD")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(WorkbenchTheme.violet)
                    Text("剪贴板历史")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(WorkbenchTheme.textPrimary)
                }

                Spacer(minLength: 16)

                HStack(spacing: 10) {
                    Picker("", selection: $filter) {
                        ForEach(Filter.allCases) { f in
                            Text(f.title).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    Toggle("监听", isOn: $store.isMonitoring)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WorkbenchTheme.textSecondary)
                        .onChange(of: store.isMonitoring) { _, on in
                            on ? store.start() : store.stop()
                        }

                    if !store.entries.isEmpty {
                        Button {
                            store.clearAll()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WorkbenchTheme.textSecondary)
                                .frame(width: 34, height: 32)
                                .background(WorkbenchTheme.panel)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(WorkbenchTheme.separator, lineWidth: 1)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("清空历史")
                    }
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WorkbenchTheme.textTertiary)
                TextField("搜索历史记录", text: $query)
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
        .padding(WorkbenchTheme.pagePadding)
    }
}

/// 单条剪贴板记录行。
private struct ClipboardRow: View {
    /// 剪贴板条目。
    let entry: ClipboardStore.Entry
    /// 点击应用（回贴）回调。
    let onApply: () -> Void
    /// 固定 / 取消固定回调。
    let onPin: () -> Void
    /// 删除回调。
    let onRemove: () -> Void

    /// 当前指针是否悬停。
    @State private var isHovered = false

    var body: some View {
        Button(action: onApply) {
            HStack(spacing: 14) {
                Image(systemName: entry.kind == .file ? "doc.fill" : "text.alignleft")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(entry.kind == .file ? WorkbenchTheme.cyan : WorkbenchTheme.neon)
                    .frame(width: 32, height: 32)
                    .background((entry.kind == .file ? WorkbenchTheme.cyan : WorkbenchTheme.neon).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.preview)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WorkbenchTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Text(entry.kind == .file ? "文件" : "文本")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(WorkbenchTheme.textTertiary)
                        if entry.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(WorkbenchTheme.violet)
                        }
                        Text(entry.createdAt, format: .dateTime.hour().minute().second())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(WorkbenchTheme.textTertiary)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Button {
                        onPin()
                    } label: {
                        Image(systemName: entry.pinned ? "pin.fill" : "pin")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(entry.pinned ? WorkbenchTheme.violet : WorkbenchTheme.textSecondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help(entry.pinned ? "取消固定" : "固定")

                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WorkbenchTheme.textSecondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                }
                .opacity(isHovered ? 1 : 0.55)
            }
            .padding(12)
            .background(isHovered ? WorkbenchTheme.panelRaised : WorkbenchTheme.panel)
            .overlay {
                RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous)
                    .stroke(isHovered ? WorkbenchTheme.violet.opacity(0.3) : WorkbenchTheme.separator, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchTheme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(WorkbenchTheme.motionQuick) { isHovered = hovered }
        }
    }
}

/// 剪贴板历史数据来源：轮询 NSPasteboard 并持久化。
@MainActor
final class ClipboardStore: ObservableObject {
    /// 单条剪贴板记录。
    struct Entry: Identifiable, Codable {
        /// 稳定标识。
        let id: UUID
        /// 记录类型。
        let kind: Kind
        /// 文本内容（文本类型）。
        let text: String?
        /// 文件路径（文件类型）。
        let filePaths: [String]?
        /// 列表预览文本。
        let preview: String
        /// 创建时间。
        let createdAt: Date
        /// 是否已固定。
        var pinned: Bool

        /// 记录类型。
        enum Kind: String, Codable {
            /// 文本片段。
            case text
            /// 文件引用。
            case file
        }
    }

    /// 历史记录（固定的始终排在前面）。
    @Published var entries: [Entry] = []
    /// 是否正在监听系统剪贴板。
    @Published var isMonitoring = true

    /// 轮询定时器。
    private var timer: Timer?
    /// 上一次读取的剪贴板变更计数。
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    /// 最大保留的非固定记录数。
    private let cap = 200

    /// 启动轮询。
    func start() {
        load()
        isMonitoring = true
        lastChangeCount = NSPasteboard.general.changeCount
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    /// 停止轮询。
    func stop() {
        timer?.invalidate()
        timer = nil
        save()
    }

    /// 轮询剪贴板变更。
    private func poll() {
        guard isMonitoring else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if let text = pb.string(forType: .string), !text.isEmpty {
            add(text: text)
        } else if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            add(paths: urls.map { $0.path })
        }
    }

    /// 添加一条文本记录（去重）。
    private func add(text: String) {
        guard entries.first(where: { $0.kind == .text && $0.text == text }) == nil else { return }
        let entry = Entry(
            id: UUID(), kind: .text, text: text, filePaths: nil,
            preview: text.replacingOccurrences(of: "\n", with: " ").prefix(120).description,
            createdAt: Date(), pinned: false
        )
        insert(entry)
    }

    /// 添加一条文件记录（去重）。
    private func add(paths: [String]) {
        guard entries.first(where: { $0.kind == .file && $0.filePaths == paths }) == nil else { return }
        let preview = paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ").prefix(120).description
        let entry = Entry(
            id: UUID(), kind: .file, text: nil, filePaths: paths,
            preview: preview, createdAt: Date(), pinned: false
        )
        insert(entry)
    }

    /// 插入记录并维持容量与排序。
    private func insert(_ entry: Entry) {
        entries.insert(entry, at: 0)
        let nonPinned = entries.filter { !$0.pinned }
        if nonPinned.count > cap {
            let overflow = nonPinned.suffix(nonPinned.count - cap)
            let ids = Set(overflow.map { $0.id })
            entries.removeAll { ids.contains($0.id) }
        }
        sort()
        save()
    }

    /// 将记录回贴为当前剪贴板内容。
    func apply(_ entry: Entry) {
        if entry.kind == .text, let text = entry.text {
            copyToPasteboard(text)
        } else if entry.kind == .file, let paths = entry.filePaths {
            let urls = paths.map { URL(fileURLWithPath: $0) }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(urls as [NSPasteboardWriting])
            lastChangeCount = pb.changeCount
        }
    }

    /// 切换固定状态。
    func togglePin(_ entry: Entry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].pinned.toggle()
        sort()
        save()
    }

    /// 删除单条记录。
    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// 清空全部（保留固定项）。
    func clearAll() {
        entries.removeAll { !$0.pinned }
        save()
    }

    /// 固定项始终置顶。
    private func sort() {
        entries.sort {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.createdAt > $1.createdAt
        }
    }

    /// 从磁盘加载历史。
    private func load() {
        guard FileManager.default.fileExists(atPath: Storage.clipboardURL.path) else { return }
        guard let data = try? Data(contentsOf: Storage.clipboardURL),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
        sort()
    }

    /// 持久化历史到磁盘。
    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: Storage.clipboardURL, options: [.atomic])
    }
}
