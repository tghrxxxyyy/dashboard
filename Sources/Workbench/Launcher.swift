import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 启动台应用排序方式。
private enum LauncherSort: String, CaseIterable, Identifiable {
    case recent
    case name
    case manual

    /// 排序选项的稳定标识。
    var id: String { rawValue }

    /// 排序选项的展示名称。
    var title: String {
        switch self {
        case .recent: return "最近"
        case .name: return "名称"
        case .manual: return "默认"
        }
    }
}

/// 管理启动台分组、应用记录与本地持久化。
@MainActor
final class LauncherStore: ObservableObject {
    /// 启动台中的全部分组。
    @Published var tags: [LauncherTag]
    /// 当前选中的分组标识。
    @Published var selectedTagId: UUID? {
        didSet {
            UserDefaults.standard.set(selectedTagId?.uuidString, forKey: Self.selectedTagKey)
        }
    }
    /// 最近一次读写或启动错误。
    @Published var errorMessage: String?
    /// 最近一次成功操作提示。
    @Published var noticeMessage: String?

    private static let selectedTagKey = "Workbench.SelectedLauncherTag"

    /// 读取本地启动台数据并恢复最近选择。
    init() {
        do {
            let loadedTags = try Storage.loadLauncher()
            tags = loadedTags
            if let rawID = UserDefaults.standard.string(forKey: Self.selectedTagKey),
               let restoredID = UUID(uuidString: rawID),
               loadedTags.contains(where: { $0.id == restoredID }) {
                selectedTagId = restoredID
            } else {
                selectedTagId = loadedTags.first?.id
            }
        } catch {
            tags = []
            selectedTagId = nil
            errorMessage = error.localizedDescription
        }
    }

    /// 当前选中的启动台分组。
    var selectedTag: LauncherTag? {
        tags.first(where: { $0.id == selectedTagId })
    }

    /// 启动台中的全部应用记录。
    var allApps: [AppItem] {
        tags.flatMap(\.items)
    }

    /// 已收藏的应用，按最近启动时间排列。
    var favoriteApps: [AppItem] {
        allApps
            .filter(\.isFavorite)
            .sorted { ($0.lastLaunchedAt ?? .distantPast) > ($1.lastLaunchedAt ?? .distantPast) }
    }

    /// 最近启动的应用，最多返回八条。
    var recentApps: [AppItem] {
        Array(
            allApps
                .filter { $0.lastLaunchedAt != nil }
                .sorted { ($0.lastLaunchedAt ?? .distantPast) > ($1.lastLaunchedAt ?? .distantPast) }
                .prefix(8)
        )
    }

    /// 新建启动台分组。
    /// - Parameter name: 用户输入的分组名称。
    func addTag(name: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return }
        guard !tags.contains(where: { $0.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame }) else {
            errorMessage = "已经存在同名分组。"
            return
        }
        let tag = LauncherTag(id: UUID(), name: normalizedName, items: [])
        tags.append(tag)
        selectedTagId = tag.id
        persist(notice: "已创建 \(normalizedName)")
    }

    /// 重命名指定启动台分组。
    /// - Parameters:
    ///   - id: 待重命名的分组标识。
    ///   - name: 新分组名称。
    func renameTag(_ id: UUID, name: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              let index = tags.firstIndex(where: { $0.id == id }) else { return }
        guard !tags.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(normalizedName) == .orderedSame }) else {
            errorMessage = "已经存在同名分组。"
            return
        }
        tags[index].name = normalizedName
        persist(notice: "分组已重命名")
    }

    /// 删除指定分组及其启动台记录。
    /// - Parameter id: 待删除的分组标识。
    func deleteTag(_ id: UUID) {
        tags.removeAll { $0.id == id }
        if selectedTagId == id {
            selectedTagId = tags.first?.id
        }
        persist(notice: "分组已移除")
    }

    /// 将多个应用加入当前分组，并自动忽略重复项。
    /// - Parameter urls: 用户选择或拖入的应用包地址。
    func addApplications(from urls: [URL]) {
        guard let tagIndex = tags.firstIndex(where: { $0.id == selectedTagId }) else {
            errorMessage = "请先创建或选择一个分组。"
            return
        }
        let appURLs = urls.filter { $0.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame }
        guard !appURLs.isEmpty else {
            errorMessage = "仅支持添加 .app 应用程序。"
            return
        }

        var addedCount = 0
        for url in appURLs {
            let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
            let isDuplicate = tags[tagIndex].items.contains { item in
                item.path == url.path || (bundleIdentifier != nil && item.bundleId == bundleIdentifier)
            }
            guard !isDuplicate else { continue }
            tags[tagIndex].items.append(
                AppItem(
                    id: UUID(),
                    name: url.deletingPathExtension().lastPathComponent,
                    path: url.path,
                    bundleId: bundleIdentifier
                )
            )
            addedCount += 1
        }
        guard addedCount > 0 else {
            errorMessage = "所选应用已经在当前分组中。"
            return
        }
        persist(notice: "已添加 \(addedCount) 个应用")
    }

    /// 从所在分组移除应用记录，不会删除真实应用。
    /// - Parameter item: 待移除的应用记录。
    func deleteApp(_ item: AppItem) {
        guard let tagIndex = tagIndex(containing: item.id) else { return }
        tags[tagIndex].items.removeAll { $0.id == item.id }
        persist(notice: "已从启动台移除 \(item.name)")
    }

    /// 切换应用的常用状态。
    /// - Parameter item: 要更新的应用记录。
    func toggleFavorite(_ item: AppItem) {
        guard let location = appLocation(for: item.id) else { return }
        tags[location.tag].items[location.item].isFavorite.toggle()
        persist(notice: tags[location.tag].items[location.item].isFavorite ? "已加入常用" : "已取消常用")
    }

    /// 启动应用或切换到已运行应用，并记录启动历史。
    /// - Parameter item: 要启动的应用记录。
    func launch(_ item: AppItem) {
        guard let location = appLocation(for: item.id) else { return }
        var resolvedURL = URL(fileURLWithPath: tags[location.tag].items[location.item].path)

        // 原路径失效时优先使用 bundle id 自动查找应用的新位置。
        if !FileManager.default.fileExists(atPath: resolvedURL.path),
           let bundleIdentifier = item.bundleId,
           let repairedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            resolvedURL = repairedURL
            tags[location.tag].items[location.item].path = repairedURL.path
        }
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            errorMessage = "找不到 \(item.name)，应用可能已被移动或删除。"
            return
        }
        guard NSWorkspace.shared.open(resolvedURL) else {
            errorMessage = "无法启动 \(item.name)。"
            return
        }
        tags[location.tag].items[location.item].launchCount += 1
        tags[location.tag].items[location.item].lastLaunchedAt = Date()
        persist(notice: nil)
    }

    /// 在 Finder 中定位指定应用。
    /// - Parameter item: 要定位的应用记录。
    func revealInFinder(_ item: AppItem) {
        let url = URL(fileURLWithPath: item.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "应用路径已经失效。"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 清除当前界面提示。
    func clearFeedback() {
        errorMessage = nil
        noticeMessage = nil
    }

    /// 查找包含指定应用的分组索引。
    /// - Parameter appID: 应用记录标识。
    /// - Returns: 分组索引；不存在时返回 nil。
    private func tagIndex(containing appID: UUID) -> Int? {
        tags.firstIndex { tag in tag.items.contains(where: { $0.id == appID }) }
    }

    /// 查找应用在二维分组数据中的准确位置。
    /// - Parameter appID: 应用记录标识。
    /// - Returns: 分组与应用索引；不存在时返回 nil。
    private func appLocation(for appID: UUID) -> (tag: Int, item: Int)? {
        for tagIndex in tags.indices {
            if let itemIndex = tags[tagIndex].items.firstIndex(where: { $0.id == appID }) {
                return (tagIndex, itemIndex)
            }
        }
        return nil
    }

    /// 将当前启动台状态写入磁盘并发布操作反馈。
    /// - Parameter notice: 保存成功后显示的可选提示。
    private func persist(notice: String?) {
        do {
            try Storage.saveLauncher(tags)
            errorMessage = nil
            noticeMessage = notice
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 启动台主界面。
struct LauncherView: View {
    /// 启动台数据源。
    @ObservedObject var store: LauncherStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var sort: LauncherSort = .recent
    @State private var showTagEditor = false
    @State private var editingTag: LauncherTag?
    @State private var pendingDeleteTag: LauncherTag?
    @State private var pendingDeleteApp: AppItem?

    private let gridColumns = [GridItem(.adaptive(minimum: 154, maximum: 186), spacing: 14)]

    var body: some View {
        HStack(spacing: 0) {
            tagRail
            Rectangle()
                .fill(WorkbenchTheme.overlay(0.08))
                .frame(width: 1)
            mainContent
        }
        .background(WorkbenchTheme.canvas)
        .sheet(isPresented: $showTagEditor) {
            LauncherTagEditor(title: "新建分组", initialName: "") { name in
                store.addTag(name: name)
            }
        }
        .sheet(item: $editingTag) { tag in
            LauncherTagEditor(title: "重命名分组", initialName: tag.name) { name in
                store.renameTag(tag.id, name: name)
            }
        }
        .confirmationDialog(
            "删除“\(pendingDeleteTag?.name ?? "")”？",
            isPresented: Binding(
                get: { pendingDeleteTag != nil },
                set: { if !$0 { pendingDeleteTag = nil } }
            )
        ) {
            Button("删除分组", role: .destructive) {
                if let tag = pendingDeleteTag { store.deleteTag(tag.id) }
                pendingDeleteTag = nil
            }
        } message: {
            Text("只会删除 Workbench 中的分组与快捷方式，不会卸载应用。")
        }
        .confirmationDialog(
            "移除“\(pendingDeleteApp?.name ?? "")”？",
            isPresented: Binding(
                get: { pendingDeleteApp != nil },
                set: { if !$0 { pendingDeleteApp = nil } }
            )
        ) {
            Button("从启动台移除", role: .destructive) {
                if let item = pendingDeleteApp { store.deleteApp(item) }
                pendingDeleteApp = nil
            }
        } message: {
            Text("真实应用及其数据不会被删除。")
        }
        .overlay(alignment: .bottom) { feedbackBanner }
    }

    private var tagRail: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("COLLECTIONS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WorkbenchTheme.overlay(0.42))
                    Text("应用分组")
                        .font(.system(size: 17, weight: .semibold))
                }
                Spacer()
                Button { showTagEditor = true } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(WorkbenchTheme.overlay(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .help("新建分组")
            }

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(store.tags.enumerated()), id: \.element.id) { index, tag in
                        tagButton(tag, index: index)
                    }
                }
            }

            if store.tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.title2)
                        .foregroundStyle(WorkbenchTheme.neon)
                    Text("建立第一个分组，开始组织你的工作流。")
                        .font(.caption)
                        .foregroundStyle(WorkbenchTheme.overlay(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
            }
            Spacer(minLength: 0)
            Text("\(store.tags.count) 组 · \(store.allApps.count) 个应用")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.overlay(0.35))
        }
        .padding(20)
        .frame(width: 226)
        .background(Color.black.opacity(0.22))
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let tag = store.selectedTag {
                controlBar(for: tag)
                if displayedApps.isEmpty {
                    emptyState(for: tag)
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 14) {
                            ForEach(displayedApps) { item in
                                LauncherAppCard(
                                    item: item,
                                    onLaunch: { store.launch(item) },
                                    onFavorite: { store.toggleFavorite(item) },
                                    onReveal: { store.revealInFinder(item) },
                                    onDelete: { pendingDeleteApp = item }
                                )
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                noSelectionState
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dropDestination(for: URL.self) { urls, _ in
            store.addApplications(from: urls)
            return urls.contains { $0.pathExtension.localizedCaseInsensitiveCompare("app") == .orderedSame }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LAUNCH / 02")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.neon)
                Text("启动台")
                    .font(.system(size: 30, weight: .bold))
                Text("把高频应用组织成能快速进入状态的工作场景。")
                    .font(.callout)
                    .foregroundStyle(WorkbenchTheme.overlay(0.52))
            }
            Spacer()
            Button(action: pickApplications) {
                Label("添加应用", systemImage: "plus")
                    .padding(.horizontal, 12)
                    .frame(height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.black)
            .background(WorkbenchTheme.neon)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .disabled(store.selectedTag == nil)
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }

    private var displayedApps: [AppItem] {
        guard let apps = store.selectedTag?.items else { return [] }
        let filtered = searchText.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.bundleId?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        switch sort {
        case .recent:
            return filtered.sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return ($0.lastLaunchedAt ?? .distantPast) > ($1.lastLaunchedAt ?? .distantPast)
            }
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .manual:
            return filtered
        }
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if let message = store.errorMessage ?? store.noticeMessage {
            HStack(spacing: 10) {
                Image(systemName: store.errorMessage == nil ? "checkmark" : "exclamationmark.triangle.fill")
                Text(message)
                    .lineLimit(2)
                Button { store.clearFeedback() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .font(.callout)
            .foregroundStyle(store.errorMessage == nil ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(store.errorMessage == nil ? WorkbenchTheme.neon : WorkbenchTheme.coral)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: message)
        }
    }

    /// 创建侧栏分组按钮及其上下文操作。
    /// - Parameters:
    ///   - tag: 要显示的分组。
    ///   - index: 分组在侧栏中的位置。
    /// - Returns: 可选择的分组按钮。
    private func tagButton(_ tag: LauncherTag, index: Int) -> some View {
        let selected = store.selectedTagId == tag.id
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                store.selectedTagId = tag.id
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tagIcon(index: index))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.black : WorkbenchTheme.overlay(0.55))
                Text(tag.name)
                    .lineLimit(1)
                Spacer()
                Text("\(tag.items.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(selected ? Color.black.opacity(0.58) : WorkbenchTheme.overlay(0.34))
            }
            .font(.callout.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.black : WorkbenchTheme.overlay(0.78))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
            .background(selected ? WorkbenchTheme.neon : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("重命名", systemImage: "pencil") { editingTag = tag }
            Button("删除", systemImage: "trash", role: .destructive) { pendingDeleteTag = tag }
        }
    }

    /// 根据分组位置生成稳定且有区分度的 SF Symbol。
    /// - Parameter index: 分组索引。
    /// - Returns: SF Symbol 名称。
    private func tagIcon(index: Int) -> String {
        let icons = ["square.grid.2x2", "hammer", "paintbrush", "bubble.left.and.bubble.right", "shippingbox", "ellipsis"]
        return icons[index % icons.count]
    }

    /// 创建当前分组的搜索、排序与统计工具栏。
    /// - Parameter tag: 当前选中的分组。
    /// - Returns: 分组控制栏。
    private func controlBar(for tag: LauncherTag) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WorkbenchTheme.overlay(0.36))
                TextField("搜索应用", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(WorkbenchTheme.overlay(0.36))
                        .help("清除搜索")
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: 320, minHeight: 34)
            .background(WorkbenchTheme.overlay(0.06))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(WorkbenchTheme.overlay(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Picker("排序", selection: $sort) {
                ForEach(LauncherSort.allCases) { option in Text(option.title).tag(option) }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
            Spacer()
            Text("\(displayedApps.count) / \(tag.items.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.overlay(0.4))
        }
    }

    /// 创建当前分组的空结果状态。
    /// - Parameter tag: 当前选中的分组。
    /// - Returns: 空状态视图。
    private func emptyState(for tag: LauncherTag) -> some View {
        VStack(spacing: 14) {
            Image(systemName: searchText.isEmpty ? "app.dashed" : "magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(WorkbenchTheme.cyan)
            Text(searchText.isEmpty ? "\(tag.name) 还没有应用" : "没有匹配的应用")
                .font(.title3.weight(.semibold))
            Text(searchText.isEmpty ? "添加多个应用，或直接把 .app 拖到这里。" : "换一个关键词，或者清除当前搜索。")
                .font(.callout)
                .foregroundStyle(WorkbenchTheme.overlay(0.48))
            if searchText.isEmpty {
                Button(action: pickApplications) {
                    Label("添加应用", systemImage: "plus")
                }
            } else {
                Button("清除搜索") { searchText = "" }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSelectionState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("01")
                .font(.system(size: 74, weight: .black, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.coral)
            Text("先创建一个应用分组")
                .font(.title2.bold())
            Text("按项目、角色或场景组织应用。分组只保存快捷方式，不改变系统中的应用。")
                .foregroundStyle(WorkbenchTheme.overlay(0.5))
                .frame(maxWidth: 440, alignment: .leading)
            Button {
                showTagEditor = true
            } label: {
                Label("新建分组", systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// 打开系统应用选择器并批量添加 .app。
    private func pickApplications() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.prompt = "添加到启动台"
        if panel.runModal() == .OK {
            store.addApplications(from: panel.urls)
        }
    }
}

/// 可启动、收藏并管理的单个应用卡片。
private struct LauncherAppCard: View {
    /// 当前应用记录。
    let item: AppItem
    /// 启动应用操作。
    let onLaunch: () -> Void
    /// 切换常用状态操作。
    let onFavorite: () -> Void
    /// 在 Finder 中显示操作。
    let onReveal: () -> Void
    /// 从启动台移除操作。
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var isAvailable: Bool {
        FileManager.default.fileExists(atPath: item.path)
    }

    var body: some View {
        Button(action: onLaunch) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 50, height: 50)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isAvailable ? WorkbenchTheme.neon : WorkbenchTheme.coral)
                            .frame(width: 5, height: 5)
                        Text(isAvailable ? (item.launchCount == 0 ? "READY" : "OPENED \(item.launchCount)×") : "PATH LOST")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(WorkbenchTheme.overlay(0.42))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovering ? WorkbenchTheme.overlay(0.105) : WorkbenchTheme.overlay(0.055))
        .overlay(alignment: .topTrailing) {
            Button(action: onFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(item.isFavorite ? WorkbenchTheme.neon : WorkbenchTheme.overlay(0.42))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Color.black.opacity(hovering ? 0.28 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(14)
            .help(item.isFavorite ? "取消常用" : "加入常用")
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(item.isFavorite ? WorkbenchTheme.neon : Color.clear)
                .frame(height: 2)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WorkbenchTheme.overlay(hovering ? 0.16 : 0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .offset(y: hovering && !reduceMotion ? -2 : 0)
        .shadow(color: Color.black.opacity(hovering ? 0.28 : 0), radius: 14, y: 7)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("启动 / 切换", systemImage: "arrow.up.right") { onLaunch() }
            Button(item.isFavorite ? "取消常用" : "加入常用", systemImage: item.isFavorite ? "star.slash" : "star") { onFavorite() }
            Button("在 Finder 中显示", systemImage: "folder") { onReveal() }
            Divider()
            Button("移除", systemImage: "trash", role: .destructive) { onDelete() }
        }
        .help("启动或切换到 \(item.name)")
    }
}

/// 新建或重命名启动台分组的紧凑编辑器。
private struct LauncherTagEditor: View {
    /// 编辑器标题。
    let title: String
    /// 初始分组名称。
    let initialName: String
    /// 提交名称的回调。
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var name: String

    /// 创建分组编辑器。
    /// - Parameters:
    ///   - title: 编辑器标题。
    ///   - initialName: 初始分组名称。
    ///   - onSubmit: 提交名称的回调。
    init(title: String, initialName: String, onSubmit: @escaping (String) -> Void) {
        self.title = title
        self.initialName = initialName
        self.onSubmit = onSubmit
        _name = State(initialValue: initialName)
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COLLECTION")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.neon)
                Text(title).font(.title2.bold())
            }
            TextField("例如：开发、设计、沟通", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("完成", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(normalizedName.isEmpty || normalizedName == initialName)
            }
        }
        .padding(24)
        .frame(width: 390)
        .onAppear { focused = true }
    }

    /// 提交修剪后的分组名称并关闭编辑器。
    private func submit() {
        guard !normalizedName.isEmpty else { return }
        onSubmit(normalizedName)
        dismiss()
    }
}
