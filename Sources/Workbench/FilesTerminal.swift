import SwiftUI
import AppKit

/// 文件搜索的无状态运行参数。
private enum FileSearchConfiguration {
    /// 单次查询最多展示的结果数。
    static let resultLimit = 120

    /// 单次 Spotlight 输出最多保留的字节数。
    static let outputLimit = 640_000
}

/// Spotlight 返回的结构化文件结果。
private struct FileSearchResult: Identifiable, Hashable, Sendable {
    /// 文件的标准化 URL，也是打开与 Finder 定位的唯一来源。
    let url: URL

    /// 文件或目录名称。
    let name: String

    /// 文件所在的父目录路径。
    let parentPath: String

    /// 系统提供的本地化文件类型描述。
    let kind: String

    /// 文件字节数，目录或无法读取时为 nil。
    let byteSize: Int64?

    /// 最后修改时间，无法读取时为 nil。
    let modifiedAt: Date?

    /// 是否为目录。
    let isDirectory: Bool

    /// 使用标准化路径作为稳定标识。
    var id: String { url.path }

    /// 文件的完整标准化路径。
    var path: String { url.path }

    /// 从 Spotlight 输出路径创建结构化结果。
    /// - Parameter path: Spotlight 返回的文件系统绝对路径。
    init(path: String) {
        let normalizedURL = URL(fileURLWithPath: path).standardizedFileURL
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .localizedTypeDescriptionKey
        ]
        let values = try? normalizedURL.resourceValues(forKeys: resourceKeys)
        let directory = values?.isDirectory ?? false

        url = normalizedURL
        name = normalizedURL.lastPathComponent.isEmpty ? normalizedURL.path : normalizedURL.lastPathComponent
        parentPath = normalizedURL.deletingLastPathComponent().path
        kind = values?.localizedTypeDescription ?? (directory ? "文件夹" : "文件")
        byteSize = directory ? nil : values?.fileSize.map { Int64($0) }
        modifiedAt = values?.contentModificationDate
        isDirectory = directory
    }
}

/// 一次文件搜索在后台完成后的载荷。
private struct FileSearchResponse: Sendable {
    /// 命令执行结果。
    let shellResult: ShellResult

    /// 已完成元数据读取的文件结果。
    let files: [FileSearchResult]
}

@MainActor
private final class FileSearchModel: ObservableObject {
    /// 用户当前输入的搜索词。
    @Published var query = ""

    /// 当前可见的结构化结果。
    @Published private(set) var results: [FileSearchResult] = []

    /// 当前详情面板选中的结果标识。
    @Published var selectedResultID: FileSearchResult.ID?

    /// 是否正在执行 Spotlight 查询。
    @Published private(set) var searching = false

    /// 是否已经完成或发起过至少一次有效查询。
    @Published private(set) var hasSearched = false

    /// 最近一次查询失败信息。
    @Published private(set) var errorMessage: String?

    /// 复制、打开等轻量操作的即时反馈。
    @Published private(set) var feedbackMessage: String?

    /// 输入搜索词后的去抖任务。
    private var debounceTask: Task<Void, Never>?

    /// 当前正在等待的搜索任务。
    private var searchTask: Task<Void, Never>?

    /// 当前有效请求标识，用于拦截旧请求覆盖新结果。
    private var activeRequestID = UUID()

    /// 自动清理轻量反馈的任务。
    private var feedbackTask: Task<Void, Never>?

    /// 当前选中的完整结果。
    var selectedResult: FileSearchResult? {
        results.first { $0.id == selectedResultID }
    }

    /// 当前结果数量摘要。
    var resultSummary: String {
        guard hasSearched else { return "等待搜索" }
        if searching { return "正在搜索" }
        if results.count == FileSearchConfiguration.resultLimit {
            return "\(results.count) 项，已达显示上限"
        }
        return "\(results.count) 项结果"
    }

    /// 根据当前输入安排一次去抖搜索；该方法没有参数，直接读取 query。
    func scheduleSearch() {
        debounceTask?.cancel()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedQuery.isEmpty else {
            resetSearch()
            return
        }

        // 输入一旦变化就让旧请求失效，避免去抖期间展示与输入不匹配的结果。
        searchTask?.cancel()
        activeRequestID = UUID()
        results = []
        selectedResultID = nil
        searching = false
        hasSearched = false
        errorMessage = nil

        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.search()
        }
    }

    /// 立即使用当前 query 发起搜索，并取消尚未触发的去抖任务。
    func search() {
        debounceTask?.cancel()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            resetSearch()
            return
        }
        beginSearch(for: normalizedQuery)
    }

    /// 使用系统默认应用打开结果。
    /// - Parameter result: 要打开的结构化文件结果。
    func open(_ result: FileSearchResult) {
        guard NSWorkspace.shared.open(result.url) else {
            showFeedback("无法打开该项目")
            return
        }
        showFeedback("已打开 \(result.name)")
    }

    /// 在 Finder 中定位并选中结果。
    /// - Parameter result: 要在 Finder 中显示的结构化文件结果。
    func revealInFinder(_ result: FileSearchResult) {
        NSWorkspace.shared.activateFileViewerSelecting([result.url])
        showFeedback("已在 Finder 中显示")
    }

    /// 复制结果的完整文件路径。
    /// - Parameter result: 要复制路径的结构化文件结果。
    func copyPath(_ result: FileSearchResult) {
        let copied = copyToPasteboard(result.path)
        showFeedback(copied ? "路径已复制" : "复制失败")
    }

    /// 清空查询相关状态，并让所有在途结果失效；该方法没有参数。
    private func resetSearch() {
        debounceTask?.cancel()
        searchTask?.cancel()
        activeRequestID = UUID()
        results = []
        selectedResultID = nil
        searching = false
        hasSearched = false
        errorMessage = nil
    }

    /// 发起一项带请求隔离的后台 Spotlight 查询。
    /// - Parameter normalizedQuery: 已去除首尾空白的查询文本。
    private func beginSearch(for normalizedQuery: String) {
        searchTask?.cancel()
        let requestID = UUID()
        activeRequestID = requestID
        searching = true
        hasSearched = true
        errorMessage = nil
        results = []
        selectedResultID = nil

        searchTask = Task { [weak self] in
            let response = await Self.loadResults(for: normalizedQuery)
            guard let self, !Task.isCancelled, self.activeRequestID == requestID else { return }

            searching = false
            if response.shellResult.exitCode == 0 {
                results = response.files
                selectedResultID = response.files.first?.id
            } else {
                let detail = response.shellResult.error.trimmingCharacters(in: .whitespacesAndNewlines)
                errorMessage = detail.isEmpty ? "Spotlight 搜索失败" : detail
            }
        }
    }

    /// 在后台执行 Spotlight 并读取文件元数据。
    /// - Parameter query: 要按文件名匹配的查询文本。
    /// - Returns: Shell 状态与结构化文件结果。
    nonisolated private static func loadResults(for query: String) async -> FileSearchResponse {
        await Task.detached(priority: .userInitiated) {
            let shellResult = Shell.run(
                executable: "/usr/bin/mdfind",
                arguments: ["-name", query],
                outputLimit: FileSearchConfiguration.outputLimit
            )
            guard shellResult.exitCode == 0 else {
                return FileSearchResponse(shellResult: shellResult, files: [])
            }

            var seenPaths = Set<String>()
            var files: [FileSearchResult] = []
            for rawLine in shellResult.output.split(whereSeparator: \.isNewline) {
                guard files.count < FileSearchConfiguration.resultLimit else { break }
                let path = String(rawLine)
                guard !path.isEmpty, !path.hasPrefix("[输出已截断") else { continue }

                // 跳过 Spotlight 残留索引及输出截断形成的不完整路径。
                guard FileManager.default.fileExists(atPath: path) else { continue }
                let file = FileSearchResult(path: path)
                guard seenPaths.insert(file.path).inserted else { continue }
                files.append(file)
            }
            return FileSearchResponse(shellResult: shellResult, files: files)
        }.value
    }

    /// 展示一条会自动消失的轻量反馈。
    /// - Parameter message: 要显示给用户的反馈文本。
    private func showFeedback(_ message: String) {
        feedbackTask?.cancel()
        feedbackMessage = message
        feedbackTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_600_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.feedbackMessage = nil
        }
    }
}

@MainActor
private final class TerminalModel: ObservableObject {
    /// 当前命令输入。
    @Published var input = ""

    /// 当前会话的终端输出。
    @Published private(set) var output = ""

    /// 是否有命令正在后台执行。
    @Published private(set) var running = false

    /// 当前会话工作目录。
    @Published private(set) var currentDirectory: URL

    /// 最近一次命令退出码。
    @Published private(set) var lastExitCode: Int?

    /// 最近一次命令耗时，单位为秒。
    @Published private(set) var lastDuration: TimeInterval?

    /// 复制或清空操作的即时反馈。
    @Published private(set) var feedbackMessage: String?

    /// 工作目录在 UserDefaults 中的键。
    private static let directoryDefaultsKey = "Workbench.Terminal.CurrentDirectory"

    /// 单次命令标准输出与标准错误各自的保留上限。
    private static let commandOutputLimit = 700_000

    /// 整个终端会话最多保留的字符数。
    private static let transcriptCharacterLimit = 1_400_000

    /// 单次会话最多保留的历史命令数量。
    private static let historyLimit = 100

    /// 上一次工作目录，用于支持 `cd -`。
    private var previousDirectory: URL?

    /// 当前会话的命令历史；出于敏感信息保护不写入磁盘。
    private var history: [String] = []

    /// 当前浏览的历史命令下标。
    private var historyIndex: Int?

    /// 开始浏览历史前尚未执行的输入草稿。
    private var historyDraft = ""

    /// 当前命令任务。
    private var runTask: Task<Void, Never>?

    /// 自动清理轻量反馈的任务。
    private var feedbackTask: Task<Void, Never>?

    /// 创建终端会话，并恢复上次有效工作目录。
    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        if let savedPath = UserDefaults.standard.string(forKey: Self.directoryDefaultsKey) {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: savedPath, isDirectory: &isDirectory), isDirectory.boolValue {
                currentDirectory = URL(fileURLWithPath: savedPath, isDirectory: true).standardizedFileURL
                return
            }
        }
        currentDirectory = homeDirectory
    }

    /// 适合工具栏展示的缩略工作目录。
    var currentDirectoryDisplay: String {
        abbreviateHome(in: currentDirectory.path)
    }

    /// 是否存在可向前浏览的命令历史。
    var canShowPreviousCommand: Bool { !history.isEmpty }

    /// 是否正在历史中且可回到更新输入。
    var canShowNextCommand: Bool { historyIndex != nil }

    /// 最近一次命令状态摘要。
    var lastRunSummary: String? {
        guard let lastExitCode, let lastDuration else { return nil }
        return "退出 \(lastExitCode) · \(String(format: "%.2f", lastDuration)) 秒"
    }

    /// 执行当前输入命令；该方法没有参数，运行期间会拒绝重复提交。
    func run() {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !running else { return }

        recordHistory(command)
        input = ""
        historyIndex = nil
        historyDraft = ""
        running = true
        lastExitCode = nil
        lastDuration = nil

        let workingDirectory = currentDirectory
        let execution = commandForExecution(command)
        let startedAt = Date()

        runTask = Task { [weak self] in
            let result = await Shell.runInBackground(
                execution.command,
                currentDirectory: workingDirectory,
                outputLimit: Self.commandOutputLimit
            )
            guard let self else { return }

            let duration = Date().timeIntervalSince(startedAt)
            if execution.changesDirectory, result.exitCode == 0 {
                updateDirectory(from: result.output, previousDirectory: workingDirectory)
            }

            // 成功的 cd 输出仅用于更新状态，不重复写入终端正文。
            let visibleOutput = execution.changesDirectory && result.exitCode == 0 ? "" : result.output
            appendExecution(
                command: command,
                standardOutput: visibleOutput,
                standardError: result.error,
                exitCode: result.exitCode,
                duration: duration
            )
            lastExitCode = result.exitCode
            lastDuration = duration
            running = false
            runTask = nil
        }
    }

    /// 将输入切换到更早的一条历史命令；该方法没有参数。
    func showPreviousCommand() {
        guard !history.isEmpty else { return }
        if let historyIndex {
            self.historyIndex = max(historyIndex - 1, 0)
        } else {
            historyDraft = input
            historyIndex = history.count - 1
        }
        if let historyIndex {
            input = history[historyIndex]
        }
    }

    /// 将输入切换到更新的一条历史命令或恢复草稿；该方法没有参数。
    func showNextCommand() {
        guard let historyIndex else { return }
        if historyIndex < history.count - 1 {
            self.historyIndex = historyIndex + 1
            input = history[historyIndex + 1]
        } else {
            self.historyIndex = nil
            input = historyDraft
        }
    }

    /// 清空当前会话输出与最近状态；该方法没有参数。
    func clear() {
        output = ""
        lastExitCode = nil
        lastDuration = nil
        showFeedback("终端输出已清空")
    }

    /// 将当前会话输出复制到系统剪贴板；该方法没有参数。
    func copyOutput() {
        guard !output.isEmpty else { return }
        let copied = copyToPasteboard(output)
        showFeedback(copied ? "终端输出已复制" : "复制失败")
    }

    /// 将用户命令转换为实际执行命令，并识别可持久化的纯 cd 操作。
    /// - Parameter command: 已去除首尾空白的用户命令。
    /// - Returns: 实际命令及其是否会改变会话目录。
    private func commandForExecution(_ command: String) -> (command: String, changesDirectory: Bool) {
        guard let directoryArgument = directoryChangeArgument(in: command) else {
            return (command, false)
        }

        let resolvedArgument: String
        if directoryArgument.isEmpty {
            resolvedArgument = FileManager.default.homeDirectoryForCurrentUser.path.shellQuoted
        } else if directoryArgument == "-", let previousDirectory {
            resolvedArgument = previousDirectory.path.shellQuoted
        } else {
            resolvedArgument = directoryArgument
        }
        return ("cd \(resolvedArgument) && /bin/pwd -P", true)
    }

    /// 提取仅包含 cd 的命令参数，复合 shell 表达式不会被拦截。
    /// - Parameter command: 已去除首尾空白的用户命令。
    /// - Returns: cd 参数；空字符串表示用户仅输入 cd，nil 表示普通命令。
    private func directoryChangeArgument(in command: String) -> String? {
        if command == "cd" { return "" }
        guard command.hasPrefix("cd ") || command.hasPrefix("cd\t") else { return nil }

        let argument = String(command.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        let compoundOperators = ["&&", "||", ";", "|", "\n"]
        guard !compoundOperators.contains(where: argument.contains) else { return nil }
        return argument
    }

    /// 使用成功 cd 命令的 pwd 输出更新并持久化工作目录。
    /// - Parameters:
    ///   - output: `/bin/pwd -P` 的标准输出。
    ///   - previousDirectory: 命令执行前的工作目录。
    private func updateDirectory(from output: String, previousDirectory: URL) {
        guard let path = output.split(whereSeparator: \.isNewline).last.map(String.init), !path.isEmpty else { return }
        let resolvedURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL

        self.previousDirectory = previousDirectory
        currentDirectory = resolvedURL
        UserDefaults.standard.set(resolvedURL.path, forKey: Self.directoryDefaultsKey)
    }

    /// 将一条命令及其输出、状态写入会话正文。
    /// - Parameters:
    ///   - command: 用户原始命令。
    ///   - standardOutput: 命令标准输出。
    ///   - standardError: 命令标准错误。
    ///   - exitCode: 子进程退出码。
    ///   - duration: 命令执行耗时，单位为秒。
    private func appendExecution(
        command: String,
        standardOutput: String,
        standardError: String,
        exitCode: Int,
        duration: TimeInterval
    ) {
        var block = output.isEmpty ? "" : "\n"
        block.append("$ \(command)\n")
        block.append(standardOutput)
        if !standardOutput.isEmpty, !standardOutput.hasSuffix("\n") {
            block.append("\n")
        }
        block.append(standardError)
        if !standardError.isEmpty, !standardError.hasSuffix("\n") {
            block.append("\n")
        }
        block.append("[退出 \(exitCode) · \(String(format: "%.2f", duration)) 秒]\n")
        output.append(block)

        // 对累计正文再次设限，避免长时间会话持续占用内存并拖慢 SwiftUI Text。
        if output.count > Self.transcriptCharacterLimit {
            output = "[更早的终端输出已省略]\n" + String(output.suffix(Self.transcriptCharacterLimit))
        }
    }

    /// 记录一条去重后的会话命令，并限制历史长度。
    /// - Parameter command: 要加入历史的完整命令。
    private func recordHistory(_ command: String) {
        if history.last != command {
            history.append(command)
        }
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }

    /// 将用户目录前缀缩写为波浪号，便于紧凑展示。
    /// - Parameter path: 要缩写的绝对路径。
    /// - Returns: 适合界面展示的路径。
    private func abbreviateHome(in path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == homePath || path.hasPrefix(homePath + "/") else { return path }
        return "~" + String(path.dropFirst(homePath.count))
    }

    /// 展示一条会自动消失的轻量反馈。
    /// - Parameter message: 要显示给用户的反馈文本。
    private func showFeedback(_ message: String) {
        feedbackTask?.cancel()
        feedbackMessage = message
        feedbackTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_600_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.feedbackMessage = nil
        }
    }
}

struct FilesTerminalView: View {
    /// 当前选中的效率工具页签。
    @State private var selectedTab = 0

    /// 在页签切换期间持续存活的文件搜索状态。
    @StateObject private var searchModel = FileSearchModel()

    /// 在页签切换期间持续存活的终端会话状态。
    @StateObject private var terminalModel = TerminalModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("效率工具", selection: $selectedTab) {
                    Label("文件搜索", systemImage: "magnifyingglass").tag(0)
                    Label("终端", systemImage: "terminal").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(WorkbenchTheme.chrome)

            Divider()

            if selectedTab == 0 {
                FileSearchView(model: searchModel)
            } else {
                TerminalView(model: terminalModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(WorkbenchTheme.neon)
    }
}

private struct FileSearchView: View {
    /// 由父视图持有的搜索状态。
    @ObservedObject var model: FileSearchModel

    /// 搜索框焦点状态。
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WorkbenchTheme.textSecondary)
                TextField("搜索本机文件", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFieldFocused)
                    .onSubmit { model.search() }
                    .onChange(of: model.query) { _, _ in model.scheduleSearch() }
                if !model.query.isEmpty {
                    Button(action: { model.query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WorkbenchTheme.textSecondary)
                    .help("清空搜索")
                }
                Button(action: { model.search() }) {
                    Image(systemName: "arrow.right")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("立即搜索")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(WorkbenchTheme.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WorkbenchTheme.separatorStrong, lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.top, 18)

            HStack(spacing: 8) {
                if model.searching {
                    ProgressView().controlSize(.small)
                }
                Text(model.resultSummary)
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.textSecondary)
                Spacer()
                if let feedback = model.feedbackMessage {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(WorkbenchTheme.neon)
                        .transition(.opacity)
                }
            }
            .frame(height: 34)
            .padding(.horizontal, 20)

            Divider()

            HSplitView {
                searchResults
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                Group {
                    if let selectedResult = model.selectedResult {
                        FileSearchDetailView(
                            result: selectedResult,
                            open: { model.open(selectedResult) },
                            reveal: { model.revealInFinder(selectedResult) },
                            copyPath: { model.copyPath(selectedResult) }
                        )
                    } else {
                        FileSearchSelectionPlaceholder()
                    }
                }
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360, maxHeight: .infinity)
            }
        }
        .background(WorkbenchTheme.canvas.opacity(0.72))
    }

    /// 构建搜索结果列表及其空状态。
    private var searchResults: some View {
        List(selection: $model.selectedResultID) {
            ForEach(model.results) { result in
                FileSearchRow(result: result)
                    .tag(result.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.open(result) }
                    .contextMenu {
                        Button(action: { model.open(result) }) {
                            Label("打开", systemImage: "arrow.up.forward.app")
                        }
                        Button(action: { model.revealInFinder(result) }) {
                            Label("在 Finder 中显示", systemImage: "folder")
                        }
                        Divider()
                        Button(action: { model.copyPath(result) }) {
                            Label("复制路径", systemImage: "doc.on.doc")
                        }
                    }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(WorkbenchTheme.canvas.opacity(0.45))
        .overlay {
            if let error = model.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text("搜索失败").font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(WorkbenchTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Button("重试") { model.search() }
                }
                .frame(maxWidth: 320)
            } else if !model.searching, model.results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: model.hasSearched ? "doc.text.magnifyingglass" : "sparkle.magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundStyle(WorkbenchTheme.textTertiary)
                    Text(model.hasSearched ? "未找到匹配文件" : "文件搜索")
                        .font(.headline)
                        .foregroundStyle(WorkbenchTheme.textPrimary)
                    Text(model.hasSearched ? "尝试更短或不同的关键词" : "Spotlight")
                        .font(.caption)
                        .foregroundStyle(WorkbenchTheme.textTertiary)
                }
            }
        }
    }
}

private struct FileSearchRow: View {
    /// 当前行展示的文件结果。
    let result: FileSearchResult

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: result.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(WorkbenchTheme.textPrimary)
                    .lineLimit(1)
                Text(result.parentPath)
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text(result.kind)
                .font(.caption2)
                .foregroundStyle(WorkbenchTheme.textTertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

private struct FileSearchDetailView: View {
    /// 当前详情结果。
    let result: FileSearchResult

    /// 打开结果的动作。
    let open: () -> Void

    /// 在 Finder 中定位结果的动作。
    let reveal: () -> Void

    /// 复制结果路径的动作。
    let copyPath: () -> Void

    /// 适合详情面板显示的文件大小。
    private var sizeText: String {
        guard let byteSize = result.byteSize else { return result.isDirectory ? "文件夹" : "未知" }
        return ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    /// 适合详情面板显示的修改时间。
    private var modifiedText: String {
        guard let modifiedAt = result.modifiedAt else { return "未知" }
        return modifiedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: result.path))
                        .resizable()
                        .frame(width: 64, height: 64)
                    Text(result.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WorkbenchTheme.textPrimary)
                        .lineLimit(3)
                    Text(result.kind)
                        .font(.caption)
                        .foregroundStyle(WorkbenchTheme.textSecondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("大小", value: sizeText)
                    LabeledContent("修改时间", value: modifiedText)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("完整路径")
                            .font(.caption)
                            .foregroundStyle(WorkbenchTheme.textSecondary)
                        Text(result.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(WorkbenchTheme.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                VStack(spacing: 8) {
                    Button(action: open) {
                        Label("打开", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(action: reveal) {
                        Label("在 Finder 中显示", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    Button(action: copyPath) {
                        Label("复制路径", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(20)
        }
        .background(WorkbenchTheme.panel.opacity(0.72))
    }
}

private struct FileSearchSelectionPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 26))
                .foregroundStyle(WorkbenchTheme.textTertiary)
            Text("选择文件查看详情")
                .font(.callout)
                .foregroundStyle(WorkbenchTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkbenchTheme.panel.opacity(0.72))
    }
}

private struct TerminalView: View {
    /// 由父视图持有的终端会话状态。
    @ObservedObject var model: TerminalModel

    /// 终端输出底部滚动锚点。
    @Namespace private var outputBottomID

    /// 命令输入框焦点状态。
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            terminalToolbar
            terminalOutput
            commandBar
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkbenchTheme.canvas.opacity(0.72))
    }

    /// 构建工作目录、运行状态与输出操作工具栏。
    private var terminalToolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(WorkbenchTheme.neon)
            VStack(alignment: .leading, spacing: 2) {
                Text("工作目录")
                    .font(.caption2)
                    .foregroundStyle(WorkbenchTheme.textSecondary)
                Text(model.currentDirectoryDisplay)
                    .font(.callout.monospaced())
                    .foregroundStyle(WorkbenchTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if model.running {
                ProgressView().controlSize(.small)
                Text("运行中")
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.textSecondary)
            } else if let summary = model.lastRunSummary {
                Circle()
                    .fill(model.lastExitCode == 0 ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Text(summary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(WorkbenchTheme.textSecondary)
                    .lineLimit(1)
            }
            if let feedback = model.feedbackMessage {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.neon)
                    .lineLimit(1)
            }
            Button(action: { model.copyOutput() }) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(model.output.isEmpty)
            .help("复制终端输出")
            Button(action: { model.clear() }) {
                Image(systemName: "trash")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(model.output.isEmpty)
            .help("清空终端输出")
        }
        .frame(minHeight: 36)
    }

    /// 构建受上限保护且自动滚动到底部的终端输出区。
    private var terminalOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.output.isEmpty ? "$" : model.output)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(
                            model.output.isEmpty ? WorkbenchTheme.textTertiary : WorkbenchTheme.textPrimary
                        )
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear
                        .frame(height: 1)
                        .id(outputBottomID)
                }
                .padding(14)
            }
            .background(WorkbenchTheme.input)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WorkbenchTheme.separatorStrong, lineWidth: 1)
            )
            .onChange(of: model.output) { _, _ in
                proxy.scrollTo(outputBottomID, anchor: .bottom)
            }
        }
    }

    /// 构建带历史导航和提交状态的命令输入栏。
    private var commandBar: some View {
        HStack(spacing: 8) {
            Text("$ ")
                .font(.body.monospaced().weight(.semibold))
                .foregroundStyle(WorkbenchTheme.neon)
            TextField("输入命令", text: $model.input)
                .textFieldStyle(.plain)
                .font(.body.monospaced())
                .focused($inputFocused)
                .disabled(model.running)
                .onSubmit { model.run() }
            Button(action: { model.showPreviousCommand() }) {
                Image(systemName: "chevron.up")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .disabled(!model.canShowPreviousCommand || model.running)
            .help("上一条命令")
            Button(action: { model.showNextCommand() }) {
                Image(systemName: "chevron.down")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .disabled(!model.canShowNextCommand || model.running)
            .help("下一条命令")
            Button(action: { model.run() }) {
                Image(systemName: "play.fill")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.running)
            .help("执行命令")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(WorkbenchTheme.input)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(WorkbenchTheme.separatorStrong, lineWidth: 1)
        )
    }
}
