import SwiftUI
import AppKit
import CryptoKit
import CommonCrypto
import Security

/// 保险库加密与随机数生成错误。
private enum CryptoVaultError: LocalizedError {
    /// PBKDF2 密钥派生失败。
    case keyDerivationFailed
    /// 系统安全随机数生成失败。
    case randomGenerationFailed

    /// 面向界面的错误说明。
    var errorDescription: String? {
        switch self {
        case .keyDerivationFailed: return "无法派生保险库密钥。"
        case .randomGenerationFailed: return "无法生成安全随机数。"
        }
    }
}

/// 提供保险库使用的 PBKDF2 与 AES-GCM 加密能力。
private enum CryptoVault {
    /// 使用 PBKDF2-HMAC-SHA256 派生 256 位对称密钥。
    /// - Parameters:
    ///   - password: 用户输入的主密码。
    ///   - salt: 每个保险库独立的随机盐。
    ///   - rounds: PBKDF2 迭代次数。
    /// - Returns: 可用于 AES-GCM 的对称密钥。
    static func deriveKey(password: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        var derived = Data(count: 32)
        let passwordData = Data(password.utf8)
        let status = derived.withUnsafeMutableBytes { derivedPointer in
            passwordData.withUnsafeBytes { passwordPointer in
                salt.withUnsafeBytes { saltPointer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPointer.bindMemory(to: CChar.self).baseAddress,
                        passwordData.count,
                        saltPointer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(rounds),
                        derivedPointer.bindMemory(to: UInt8.self).baseAddress,
                        32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoVaultError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }

    /// 使用系统安全随机源生成指定长度的数据。
    /// - Parameter count: 需要生成的字节数。
    /// - Returns: 安全随机数据。
    static func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { pointer in
            SecRandomCopyBytes(kSecRandomDefault, count, pointer.baseAddress!)
        }
        guard status == errSecSuccess else { throw CryptoVaultError.randomGenerationFailed }
        return data
    }

    /// 使用 AES-GCM 加密保险库明文。
    /// - Parameters:
    ///   - plaintext: 待加密的 Codable 数据。
    ///   - key: PBKDF2 派生密钥。
    /// - Returns: nonce、认证标签与密文。
    static func encrypt(_ plaintext: Data, key: SymmetricKey) throws -> (nonce: Data, tag: Data, ciphertext: Data) {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        return (Data(sealed.nonce), Data(sealed.tag), Data(sealed.ciphertext))
    }

    /// 使用 AES-GCM 验证并解密保险库密文。
    /// - Parameters:
    ///   - nonce: 加密时生成的随机 nonce。
    ///   - tag: AES-GCM 认证标签。
    ///   - ciphertext: 加密后的条目数据。
    ///   - key: PBKDF2 派生密钥。
    /// - Returns: 通过认证的明文数据。
    static func decrypt(nonce: Data, tag: Data, ciphertext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: ciphertext,
            tag: tag
        )
        return try AES.GCM.open(box, using: key)
    }
}

/// 新版单文件保险库加密信封。
private struct VaultEnvelope: Codable {
    /// 信封结构版本。
    let schemaVersion: Int
    /// PBKDF2 迭代次数。
    let kdfRounds: Int
    /// PBKDF2 随机盐。
    let salt: Data
    /// AES-GCM nonce。
    let nonce: Data
    /// AES-GCM 认证标签。
    let tag: Data
    /// AES-GCM 密文。
    let ciphertext: Data
    /// 信封最近写入时间。
    let updatedAt: Date
}

/// 旧版双文件保险库元数据，仅用于兼容迁移。
private struct LegacyVaultMeta: Codable {
    /// PBKDF2 随机盐。
    let salt: Data
    /// AES-GCM nonce。
    let nonce: Data
    /// AES-GCM 认证标签。
    let tag: Data
}

/// 磁盘上保险库文件的完整性状态。
enum VaultAvailability {
    /// 尚未创建保险库。
    case new
    /// 新版保险库可用。
    case ready
    /// 旧版保险库完整，可在解锁后迁移。
    case legacy
    /// 保险库文件不完整或无法安全识别。
    case damaged
}

/// 管理保险库解锁状态、加密持久化与安全辅助行为。
@MainActor
final class SecretsStore: ObservableObject {
    /// 保险库是否已解锁。
    @Published var unlocked = false
    /// 当前解密到内存中的保险库条目。
    @Published var entries: [SecretEntry] = []
    /// 最近一次错误说明。
    @Published var error: String?
    /// 最近一次成功操作提示。
    @Published var notice: String?

    private static let schemaVersion = 2
    private static let currentKDFRounds = 310_000
    private static let legacyKDFRounds = 120_000
    private static let autoLockSeconds: UInt64 = 600
    private static let clipboardSeconds: UInt64 = 45

    private var key: SymmetricKey?
    private var salt: Data?
    private var kdfRounds = currentKDFRounds
    private var autoLockTask: Task<Void, Never>?
    private var clipboardTask: Task<Void, Never>?

    /// 根据磁盘文件判断保险库能否安全解锁或创建。
    var availability: VaultAvailability {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: Storage.vaultURL.path) { return .ready }
        let hasLegacyMeta = fileManager.fileExists(atPath: Storage.metaURL.path)
        let hasLegacyData = fileManager.fileExists(atPath: Storage.dataURL.path)
        if hasLegacyMeta && hasLegacyData { return .legacy }
        if hasLegacyMeta || hasLegacyData { return .damaged }
        return .new
    }

    /// 使用主密码创建一个全新的空保险库。
    /// - Parameter password: 已由界面二次确认的主密码。
    /// - Returns: 创建并解锁成功时返回 true。
    @discardableResult
    func create(password: String) -> Bool {
        guard availability == .new, !password.isEmpty else {
            error = "当前状态无法创建新保险库。"
            return false
        }
        do {
            let newSalt = try CryptoVault.randomData(count: 16)
            let newKey = try CryptoVault.deriveKey(
                password: password,
                salt: newSalt,
                rounds: Self.currentKDFRounds
            )
            key = newKey
            salt = newSalt
            kdfRounds = Self.currentKDFRounds
            entries = []
            try writeEnvelope()
            unlocked = true
            error = nil
            notice = "保险库已创建"
            armAutoLock()
            return true
        } catch {
            clearSensitiveState()
            self.error = error.localizedDescription
            return false
        }
    }

    /// 使用主密码解锁新版或旧版保险库。
    /// - Parameter password: 用户输入的主密码。
    /// - Returns: 解锁成功时返回 true。
    @discardableResult
    func unlock(password: String) -> Bool {
        guard !password.isEmpty else { return false }
        do {
            switch availability {
            case .ready:
                try unlockCurrentVault(password: password)
            case .legacy:
                try unlockLegacyVault(password: password)
                // 迁移只新增新版信封，旧版双文件继续保留作为人工回退。
                try writeEnvelope()
                notice = "旧保险库已安全升级"
            case .new:
                error = "请先确认两次主密码以创建保险库。"
                return false
            case .damaged:
                error = "保险库文件不完整，已停止写入以保护现有数据。"
                return false
            }
            unlocked = true
            error = nil
            armAutoLock()
            return true
        } catch {
            clearSensitiveState()
            self.error = "无法解锁。请检查主密码或保险库文件。"
            return false
        }
    }

    /// 新增一个保险库条目并立即加密保存。
    /// - Parameter entry: 待新增的条目。
    func add(_ entry: SecretEntry) {
        entries.append(entry)
        persist(notice: "密钥已保存")
    }

    /// 更新已有保险库条目并刷新修改时间。
    /// - Parameter entry: 包含原条目标识的新内容。
    func update(_ entry: SecretEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updatedEntry = entry
        updatedEntry.updatedAt = Date()
        entries[index] = updatedEntry
        persist(notice: "修改已加密保存")
    }

    /// 删除保险库条目并立即加密保存。
    /// - Parameter entry: 待删除的条目。
    func remove(_ entry: SecretEntry) {
        entries.removeAll { $0.id == entry.id }
        persist(notice: "条目已删除")
    }

    /// 切换保险库条目的常用状态。
    /// - Parameter entry: 待更新的条目。
    func toggleFavorite(_ entry: SecretEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isFavorite.toggle()
        entries[index].updatedAt = Date()
        persist(notice: entries[index].isFavorite ? "已加入常用" : "已取消常用")
    }

    /// 更换主密码并使用新盐重新加密全部条目。
    /// - Parameter password: 已二次确认的新主密码。
    /// - Returns: 重新加密成功时返回 true。
    @discardableResult
    func changeMasterPassword(to password: String) -> Bool {
        guard unlocked, !password.isEmpty else { return false }
        let oldKey = key
        let oldSalt = salt
        let oldRounds = kdfRounds
        do {
            let newSalt = try CryptoVault.randomData(count: 16)
            let newKey = try CryptoVault.deriveKey(
                password: password,
                salt: newSalt,
                rounds: Self.currentKDFRounds
            )
            key = newKey
            salt = newSalt
            kdfRounds = Self.currentKDFRounds
            try writeEnvelope()
            notice = "主密码已更新"
            error = nil
            armAutoLock()
            return true
        } catch {
            key = oldKey
            salt = oldSalt
            kdfRounds = oldRounds
            self.error = "主密码更新失败，原密码仍然有效。"
            return false
        }
    }

    /// 复制字段值，并在剪贴板未被用户改写时延时清除。
    /// - Parameter value: 要复制的密钥字段值。
    func copySecurely(_ value: String) {
        copyToPasteboard(value)
        notice = "已复制，45 秒后自动清理"
        armAutoLock()
        clipboardTask?.cancel()
        clipboardTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.clipboardSeconds))
            guard !Task.isCancelled,
                  NSPasteboard.general.string(forType: .string) == value else { return }
            NSPasteboard.general.clearContents()
            self?.notice = "敏感剪贴板已清理"
        }
    }

    /// 将当前单文件密文原样导出为加密备份。
    /// - Parameter destination: 用户选择的备份目标地址。
    func exportEncryptedBackup(to destination: URL) {
        do {
            guard FileManager.default.fileExists(atPath: Storage.vaultURL.path) else {
                throw StorageError.corrupted("密钥保险库")
            }
            let encryptedData = try Data(contentsOf: Storage.vaultURL)
            try encryptedData.write(to: destination, options: [.atomic])
            notice = "加密备份已导出"
            error = nil
            armAutoLock()
        } catch {
            self.error = "导出失败：\(error.localizedDescription)"
        }
    }

    /// 清除内存中的派生密钥与明文条目并锁定界面。
    func lock() {
        autoLockTask?.cancel()
        clipboardTask?.cancel()
        clearSensitiveState()
        error = nil
        notice = nil
    }

    /// 清除当前错误与操作提示。
    func clearFeedback() {
        error = nil
        notice = nil
    }

    /// 读取并解锁新版单文件保险库。
    /// - Parameter password: 用户输入的主密码。
    private func unlockCurrentVault(password: String) throws {
        let data = try Data(contentsOf: Storage.vaultURL)
        let envelope = try JSONDecoder().decode(VaultEnvelope.self, from: data)
        guard envelope.schemaVersion <= Self.schemaVersion else {
            throw StorageError.corrupted("密钥保险库")
        }
        let derivedKey = try CryptoVault.deriveKey(
            password: password,
            salt: envelope.salt,
            rounds: envelope.kdfRounds
        )
        let plaintext = try CryptoVault.decrypt(
            nonce: envelope.nonce,
            tag: envelope.tag,
            ciphertext: envelope.ciphertext,
            key: derivedKey
        )
        entries = try JSONDecoder().decode([SecretEntry].self, from: plaintext)
        key = derivedKey
        salt = envelope.salt
        kdfRounds = envelope.kdfRounds
    }

    /// 读取并解锁旧版双文件保险库。
    /// - Parameter password: 用户输入的主密码。
    private func unlockLegacyVault(password: String) throws {
        let metadata = try JSONDecoder().decode(
            LegacyVaultMeta.self,
            from: Data(contentsOf: Storage.metaURL)
        )
        let derivedKey = try CryptoVault.deriveKey(
            password: password,
            salt: metadata.salt,
            rounds: Self.legacyKDFRounds
        )
        let plaintext = try CryptoVault.decrypt(
            nonce: metadata.nonce,
            tag: metadata.tag,
            ciphertext: Data(contentsOf: Storage.dataURL),
            key: derivedKey
        )
        entries = try JSONDecoder().decode([SecretEntry].self, from: plaintext)
        key = derivedKey
        salt = metadata.salt
        kdfRounds = Self.legacyKDFRounds
    }

    /// 使用当前内存密钥创建并原子写入新版加密信封。
    private func writeEnvelope() throws {
        guard let key, let salt else { throw StorageError.writeFailed("密钥保险库") }
        let plaintext = try JSONEncoder().encode(entries)
        let encrypted = try CryptoVault.encrypt(plaintext, key: key)
        let envelope = VaultEnvelope(
            schemaVersion: Self.schemaVersion,
            kdfRounds: kdfRounds,
            salt: salt,
            nonce: encrypted.nonce,
            tag: encrypted.tag,
            ciphertext: encrypted.ciphertext,
            updatedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try Storage.saveVault(encoder.encode(envelope))
    }

    /// 加密保存当前条目并刷新自动锁计时。
    /// - Parameter notice: 保存成功后的提示文本。
    private func persist(notice: String) {
        do {
            try writeEnvelope()
            self.notice = notice
            error = nil
            armAutoLock()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 重置十分钟无敏感操作自动锁定计时。
    private func armAutoLock() {
        autoLockTask?.cancel()
        autoLockTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.autoLockSeconds))
            guard !Task.isCancelled else { return }
            self?.lock()
        }
    }

    /// 清空保险库在内存中的敏感状态。
    private func clearSensitiveState() {
        key = nil
        salt = nil
        entries = []
        unlocked = false
    }
}

/// 密钥保险库主界面。
struct SecretsView: View {
    /// 根视图共享的保险库数据源。
    @ObservedObject var store: SecretsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var password = ""
    @State private var confirmation = ""
    @State private var searchText = ""
    @State private var selectedCategory = "全部"
    @State private var showEditor = false
    @State private var editingEntry: SecretEntry?
    @State private var pendingDeleteEntry: SecretEntry?
    @State private var showPasswordChange = false
    @FocusState private var passwordFocused: Bool

    private let lime = WorkbenchTheme.neon
    private let cyan = WorkbenchTheme.cyan
    private let coral = WorkbenchTheme.coral

    private var categories: [String] {
        ["全部"] + Array(Set(store.entries.map(\.category))).sorted()
    }

    private var displayedEntries: [SecretEntry] {
        store.entries
            .filter { entry in
                let matchesCategory = selectedCategory == "全部" || entry.category == selectedCategory
                let matchesSearch = searchText.isEmpty ||
                    entry.title.localizedCaseInsensitiveContains(searchText) ||
                    entry.category.localizedCaseInsensitiveContains(searchText) ||
                    entry.fields.contains { $0.key.localizedCaseInsensitiveContains(searchText) }
                return matchesCategory && matchesSearch
            }
            .sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return $0.updatedAt > $1.updatedAt
            }
    }

    var body: some View {
        Group {
            if store.unlocked {
                unlockedContent
            } else {
                lockedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkbenchTheme.canvas)
        .sheet(isPresented: $showEditor) {
            SecretEditView(store: store, entry: nil)
        }
        .sheet(item: $editingEntry) { entry in
            SecretEditView(store: store, entry: entry)
        }
        .sheet(isPresented: $showPasswordChange) {
            MasterPasswordChangeView(store: store)
        }
        .confirmationDialog(
            "删除“\(pendingDeleteEntry?.title ?? "")”？",
            isPresented: Binding(
                get: { pendingDeleteEntry != nil },
                set: { if !$0 { pendingDeleteEntry = nil } }
            )
        ) {
            Button("永久删除条目", role: .destructive) {
                if let entry = pendingDeleteEntry { store.remove(entry) }
                pendingDeleteEntry = nil
            }
        } message: {
            Text("该操作会立即写入加密保险库，无法撤销。")
        }
        .overlay(alignment: .bottom) { feedbackBanner }
    }

    private var unlockedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            unlockedHeader
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 18)
            filterBar
                .padding(.horizontal, 28)
                .padding(.bottom, 14)
            if displayedEntries.isEmpty {
                unlockedEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(displayedEntries) { entry in
                            SecretEntryCard(
                                entry: entry,
                                onCopy: store.copySecurely,
                                onFavorite: { store.toggleFavorite(entry) },
                                onEdit: { editingEntry = entry },
                                onDelete: { pendingDeleteEntry = entry }
                            )
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var unlockedHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Circle().fill(lime).frame(width: 7, height: 7)
                    Text("ENCRYPTED / 04")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(lime)
                }
                Text("密钥保险库")
                    .font(.system(size: 30, weight: .bold))
                Text("敏感信息只在解锁期间存在于内存，并始终以 AES-GCM 落盘。")
                    .font(.callout)
                    .foregroundStyle(WorkbenchTheme.overlay(0.52))
            }
            Spacer()
            HStack(spacing: 8) {
                Menu {
                    Button("更换主密码", systemImage: "key.horizontal") {
                        showPasswordChange = true
                    }
                    Button("导出加密备份", systemImage: "square.and.arrow.up") {
                        exportBackup()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("保险库设置")

                Button { store.lock() } label: {
                    Image(systemName: "lock.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .background(WorkbenchTheme.overlay(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .help("立即锁定")

                Button { showEditor = true } label: {
                    Label("新增密钥", systemImage: "plus")
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.black)
                .background(lime)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WorkbenchTheme.overlay(0.36))
                TextField("搜索名称、分类或字段", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(WorkbenchTheme.overlay(0.36))
                        .help("清除搜索")
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: 360, minHeight: 34)
            .background(WorkbenchTheme.overlay(0.055))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(WorkbenchTheme.overlay(0.07)))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Picker("分类", selection: $selectedCategory) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 150)
            Spacer()
            Text("\(displayedEntries.count) / \(store.entries.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.overlay(0.4))
        }
    }

    private var unlockedEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: store.entries.isEmpty ? "key.slash" : "magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(cyan)
            Text(store.entries.isEmpty ? "保险库还没有条目" : "没有匹配的密钥")
                .font(.title3.bold())
            Text(store.entries.isEmpty ? "保存 API Key、Token、账号或任意自定义字段。" : "尝试切换分类或清除搜索。")
                .font(.callout)
                .foregroundStyle(WorkbenchTheme.overlay(0.48))
            Button(store.entries.isEmpty ? "新增第一条密钥" : "清除筛选") {
                if store.entries.isEmpty {
                    showEditor = true
                } else {
                    searchText = ""
                    selectedCategory = "全部"
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lockedContent: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("VAULT / 04")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(lime)
                Spacer()
                Text("PRIVATE\nBY DEFAULT")
                    .font(.system(size: 54, weight: .black))
                    .tracking(0)
                    .fixedSize(horizontal: true, vertical: true)
                Rectangle()
                    .fill(coral)
                    .frame(width: 62, height: 5)
                Text("AES-GCM · PBKDF2-SHA256\nLOCAL ONLY · AUTO-LOCK 10 MIN")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(WorkbenchTheme.overlay(0.42))
                    .lineSpacing(5)
                Spacer()
            }
            .padding(36)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.22))

            Rectangle().fill(WorkbenchTheme.overlay(0.08)).frame(width: 1)

            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: store.availability == .damaged ? "exclamationmark.shield.fill" : "lock.shield.fill")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(store.availability == .damaged ? coral : cyan)
                VStack(alignment: .leading, spacing: 6) {
                    Text(lockTitle)
                        .font(.title2.bold())
                    Text(lockDetail)
                        .font(.callout)
                        .foregroundStyle(WorkbenchTheme.overlay(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if store.availability != .damaged {
                    SecureField("主密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .focused($passwordFocused)
                        .onSubmit(submitPassword)
                    if store.availability == .new {
                        SecureField("再次输入主密码", text: $confirmation)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(submitPassword)
                    }
                    Button(action: submitPassword) {
                        HStack {
                            Text(store.availability == .new ? "创建并解锁" : "解锁保险库")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.black)
                    .background(canSubmitPassword ? lime : WorkbenchTheme.overlay(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .disabled(!canSubmitPassword)
                    .keyboardShortcut(.defaultAction)
                }

                if let error = store.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("Workbench 无法找回主密码。请把它保存在你信任的独立位置。")
                    .font(.caption)
                    .foregroundStyle(WorkbenchTheme.overlay(0.34))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(36)
            .frame(width: 420, alignment: .leading)
        }
        .onAppear { passwordFocused = true }
    }

    private var lockTitle: String {
        switch store.availability {
        case .new: return "建立你的本地保险库"
        case .ready: return "欢迎回来"
        case .legacy: return "解锁并升级保险库"
        case .damaged: return "保险库需要人工检查"
        }
    }

    private var lockDetail: String {
        switch store.availability {
        case .new: return "首次使用需输入两次主密码。创建后明文不会写入磁盘。"
        case .ready: return "输入主密码以解密本地条目。连续十分钟无敏感操作会自动锁定。"
        case .legacy: return "输入原主密码后会写入新版单文件信封，旧文件仍会保留。"
        case .damaged: return "检测到旧保险库文件缺失。为避免覆盖可恢复数据，Workbench 已禁止创建与写入。"
        }
    }

    private var canSubmitPassword: Bool {
        guard !password.isEmpty else { return false }
        if store.availability == .new {
            return password.count >= 8 && password == confirmation
        }
        return true
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if let message = store.error ?? store.notice {
            HStack(spacing: 10) {
                Image(systemName: store.error == nil ? "checkmark" : "exclamationmark.triangle.fill")
                Text(message).lineLimit(2)
                Button { store.clearFeedback() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .help("关闭")
            }
            .font(.callout)
            .foregroundStyle(store.error == nil ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(store.error == nil ? lime : coral)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: message)
        }
    }

    /// 根据当前磁盘状态创建或解锁保险库。
    private func submitPassword() {
        guard canSubmitPassword else { return }
        let succeeded: Bool
        if store.availability == .new {
            succeeded = store.create(password: password)
        } else {
            succeeded = store.unlock(password: password)
        }
        if succeeded {
            password = ""
            confirmation = ""
        }
    }

    /// 打开保存面板并导出单文件加密备份。
    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Workbench-Vault.workbenchvault"
        panel.title = "导出加密保险库"
        if panel.runModal() == .OK, let url = panel.url {
            store.exportEncryptedBackup(to: url)
        }
    }
}

/// 可展开查看字段的保险库条目卡片。
private struct SecretEntryCard: View {
    /// 当前保险库条目。
    let entry: SecretEntry
    /// 安全复制字段值回调。
    let onCopy: (String) -> Void
    /// 切换常用状态回调。
    let onFavorite: () -> Void
    /// 编辑条目回调。
    let onEdit: () -> Void
    /// 删除条目回调。
    let onDelete: () -> Void

    @State private var expanded = false
    @State private var revealedFields: Set<UUID> = []
    @State private var copiedFieldID: UUID?

    private let lime = WorkbenchTheme.neon
    private let cyan = WorkbenchTheme.cyan

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: categoryIcon(entry.category))
                        .foregroundStyle(cyan)
                        .frame(width: 32, height: 32)
                        .background(cyan.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text("\(entry.category.uppercased()) · \(entry.fields.count) FIELDS")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(WorkbenchTheme.overlay(0.36))
                    }
                    Spacer()
                    if entry.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(lime)
                    }
                    Text(entry.updatedAt == .distantPast ? "LEGACY" : entry.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(WorkbenchTheme.overlay(0.34))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(WorkbenchTheme.overlay(0.4))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Rectangle().fill(WorkbenchTheme.overlay(0.07)).frame(height: 1)
                VStack(spacing: 2) {
                    ForEach(entry.fields) { field in
                        fieldRow(field)
                    }
                }
                .padding(10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(WorkbenchTheme.overlay(0.045))
        .overlay(alignment: .leading) {
            Rectangle().fill(entry.isFavorite ? lime : Color.clear).frame(width: 2)
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(WorkbenchTheme.overlay(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contextMenu {
            Button(entry.isFavorite ? "取消常用" : "加入常用", systemImage: entry.isFavorite ? "star.slash" : "star") { onFavorite() }
            Button("编辑", systemImage: "pencil") { onEdit() }
            Divider()
            Button("删除", systemImage: "trash", role: .destructive) { onDelete() }
        }
    }

    /// 创建一个可独立显示与复制的密钥字段行。
    /// - Parameter field: 要展示的密钥字段。
    /// - Returns: 字段行视图。
    private func fieldRow(_ field: SecretField) -> some View {
        let isRevealed = revealedFields.contains(field.id) || !field.isSensitive
        return HStack(spacing: 10) {
            Text(field.key.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(WorkbenchTheme.overlay(0.36))
                .frame(width: 112, alignment: .leading)
            Text(isRevealed ? field.value : String(repeating: "•", count: min(max(field.value.count, 8), 18)))
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer()
            if field.isSensitive {
                Button { toggleReveal(field.id) } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(WorkbenchTheme.overlay(0.45))
                .help(isRevealed ? "隐藏字段" : "显示字段")
            }
            Button { copyField(field) } label: {
                Image(systemName: copiedFieldID == field.id ? "checkmark" : "doc.on.doc")
                    .symbolEffect(.bounce, value: copiedFieldID == field.id)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(copiedFieldID == field.id ? lime : WorkbenchTheme.overlay(0.55))
            .background(WorkbenchTheme.overlay(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .help("复制字段")
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
    }

    /// 切换单个字段的明文显示状态。
    /// - Parameter id: 字段标识。
    private func toggleReveal(_ id: UUID) {
        if revealedFields.contains(id) {
            revealedFields.remove(id)
        } else {
            revealedFields.insert(id)
        }
    }

    /// 复制字段并短暂显示成功状态。
    /// - Parameter field: 要复制的字段。
    private func copyField(_ field: SecretField) {
        onCopy(field.value)
        copiedFieldID = field.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            if copiedFieldID == field.id { copiedFieldID = nil }
        }
    }

    /// 根据分类返回对应的 SF Symbol。
    /// - Parameter category: 密钥分类名称。
    /// - Returns: SF Symbol 名称。
    private func categoryIcon(_ category: String) -> String {
        switch category.lowercased() {
        case "openai", "glm": return "brain.head.profile"
        case "loki": return "waveform.path.ecg"
        case "高德": return "map"
        case "爬虫代理": return "network"
        default: return "key.horizontal"
        }
    }
}

/// 新增或编辑保险库条目的表单。
private struct SecretEditView: View {
    /// 保险库数据源。
    @ObservedObject var store: SecretsStore
    /// 编辑中的原条目；为 nil 时创建新条目。
    let entry: SecretEntry?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var category: String
    @State private var fields: [SecretField]
    @FocusState private var titleFocused: Bool

    private let categories = ["OpenAI", "GLM", "Loki", "高德", "爬虫代理", "自定义"]
    private let lime = WorkbenchTheme.neon

    /// 创建条目表单，并用已有内容或默认模板初始化状态。
    /// - Parameters:
    ///   - store: 保险库数据源。
    ///   - entry: 待编辑条目；为 nil 时表示新增。
    init(store: SecretsStore, entry: SecretEntry?) {
        self.store = store
        self.entry = entry
        _title = State(initialValue: entry?.title ?? "")
        _category = State(initialValue: entry?.category ?? "自定义")
        _fields = State(initialValue: entry?.fields ?? [SecretField(id: UUID(), key: "Key", value: "")])
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        fields.contains { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.value.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ENCRYPTED RECORD")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(lime)
                    Text(entry == nil ? "新增密钥" : "编辑密钥")
                        .font(.title2.bold())
                }
                Spacer()
                Text("\(fields.count) FIELDS")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("条目名称", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($titleFocused)
                Picker("分类", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 150)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($fields) { $field in
                        fieldEditor(field: $field)
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 320)

            HStack {
                Button { addField() } label: {
                    Label("添加字段", systemImage: "plus")
                }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("加密保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 570)
        .onAppear { titleFocused = true }
    }

    /// 创建可编辑、可生成强密码的字段行。
    /// - Parameter field: 字段双向绑定。
    /// - Returns: 字段编辑视图。
    private func fieldEditor(field: Binding<SecretField>) -> some View {
        HStack(spacing: 8) {
            TextField("字段名", text: field.key)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
            if field.wrappedValue.isSensitive {
                SecureField("字段值", text: field.value)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("字段值", text: field.value)
                    .textFieldStyle(.roundedBorder)
            }
            Button {
                field.wrappedValue.isSensitive.toggle()
            } label: {
                Image(systemName: field.wrappedValue.isSensitive ? "lock.fill" : "textformat")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(field.wrappedValue.isSensitive ? "敏感字段，保存时默认隐藏" : "普通文本字段")
            Button {
                field.wrappedValue.value = SecretGenerator.makePassword(length: 28)
                field.wrappedValue.isSensitive = true
            } label: {
                Image(systemName: "sparkles")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("生成 28 位强密码")
            Button {
                removeField(field.wrappedValue.id)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(fields.count == 1)
            .help("删除字段")
        }
        .padding(8)
        .background(WorkbenchTheme.overlay(0.045))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(WorkbenchTheme.overlay(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// 向表单追加一个空字段。
    private func addField() {
        fields.append(SecretField(id: UUID(), key: "", value: ""))
    }

    /// 从表单移除指定字段。
    /// - Parameter id: 待移除字段标识。
    private func removeField(_ id: UUID) {
        guard fields.count > 1 else { return }
        fields.removeAll { $0.id == id }
    }

    /// 规范化表单数据并新增或更新保险库条目。
    private func save() {
        let cleanFields = fields.compactMap { field -> SecretField? in
            let key = field.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !field.value.isEmpty else { return nil }
            return SecretField(id: field.id, key: key, value: field.value, isSensitive: field.isSensitive)
        }
        let result = SecretEntry(
            id: entry?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            fields: cleanFields,
            isFavorite: entry?.isFavorite ?? false,
            updatedAt: entry?.updatedAt ?? Date()
        )
        if entry == nil {
            store.add(result)
        } else {
            store.update(result)
        }
        dismiss()
    }
}

/// 更换保险库主密码的二次确认表单。
private struct MasterPasswordChangeView: View {
    /// 保险库数据源。
    @ObservedObject var store: SecretsStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""

    private var canSubmit: Bool {
        password.count >= 8 && password == confirmation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("更换主密码").font(.title2.bold())
            Text("全部条目将使用新盐和新派生密钥重新加密。")
                .font(.callout)
                .foregroundStyle(.secondary)
            SecureField("新主密码（至少 8 位）", text: $password)
                .textFieldStyle(.roundedBorder)
            SecureField("再次输入新主密码", text: $confirmation)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("重新加密") {
                    if store.changeMasterPassword(to: password) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}

/// 生成适合保险库字段的高熵密码。
private enum SecretGenerator {
    /// 从易辨识字符集合中生成指定长度的随机密码。
    /// - Parameter length: 密码字符数。
    /// - Returns: 包含大小写、数字与符号的随机密码。
    static func makePassword(length: Int) -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*-_=+")
        var generator = SystemRandomNumberGenerator()
        return String((0..<max(length, 1)).map { _ in characters.randomElement(using: &generator)! })
    }
}
