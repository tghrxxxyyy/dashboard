import Foundation

/// Workbench 本地数据读写错误。
enum StorageError: LocalizedError {
    /// 数据文件存在但无法解码。
    case corrupted(String)
    /// 数据无法安全写入磁盘。
    case writeFailed(String)

    /// 面向界面的错误说明。
    var errorDescription: String? {
        switch self {
        case .corrupted(let name):
            return "\(name) 数据已损坏，原文件仍保留在磁盘。"
        case .writeFailed(let name):
            return "无法保存 \(name)，请检查磁盘空间与目录权限。"
        }
    }
}

/// 负责 Workbench 在 Application Support 中的本地持久化。
enum Storage {
    /// Workbench 的应用支持目录。
    static let base: URL = {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Workbench", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// 启动台数据文件地址。
    static let launcherURL = base.appendingPathComponent("launcher.json")
    /// 启动台最近一次可用备份地址。
    static let launcherBackupURL = base.appendingPathComponent("launcher.backup.json")
    /// 加密保险库目录地址。
    static let secretsDir = base.appendingPathComponent("secrets", isDirectory: true)
    /// 新版单文件保险库地址。
    static let vaultURL = secretsDir.appendingPathComponent("vault.enc.json")
    /// 新版保险库最近一次可用备份地址。
    static let vaultBackupURL = secretsDir.appendingPathComponent("vault.backup.enc.json")
    /// 旧版保险库元数据地址，仅用于无损迁移。
    static let metaURL = secretsDir.appendingPathComponent("meta.json")
    /// 旧版保险库密文地址，仅用于无损迁移。
    static let dataURL = secretsDir.appendingPathComponent("data.enc")
    /// 剪贴板历史数据文件地址。
    static let clipboardURL = base.appendingPathComponent("clipboard.json")

    /// 确保保险库目录存在。
    static func ensureSecretsDir() throws {
        try FileManager.default.createDirectory(at: secretsDir, withIntermediateDirectories: true)
    }

    /// 从磁盘读取启动台分组。
    /// - Returns: 已解码的启动台分组；首次使用时返回空数组。
    static func loadLauncher() throws -> [LauncherTag] {
        guard FileManager.default.fileExists(atPath: launcherURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: launcherURL)
            return try JSONDecoder().decode([LauncherTag].self, from: data)
        } catch {
            throw StorageError.corrupted("启动台")
        }
    }

    /// 原子保存启动台分组，并在覆盖前保留最近一次备份。
    /// - Parameter tags: 需要持久化的启动台分组。
    static func saveLauncher(_ tags: [LauncherTag]) throws {
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(tags)
            try writeAtomically(data, to: launcherURL, backupURL: launcherBackupURL)
        } catch {
            throw StorageError.writeFailed("启动台")
        }
    }

    /// 原子写入保险库加密信封，并保留最近一次备份。
    /// - Parameter data: 已经加密并编码的保险库数据。
    static func saveVault(_ data: Data) throws {
        do {
            try ensureSecretsDir()
            try writeAtomically(data, to: vaultURL, backupURL: vaultBackupURL)
        } catch {
            throw StorageError.writeFailed("密钥保险库")
        }
    }

    /// 写入目标文件，并在覆盖前备份当前版本。
    /// - Parameters:
    ///   - data: 要写入的数据。
    ///   - targetURL: 目标文件地址。
    ///   - backupURL: 备份文件地址。
    private static func writeAtomically(_ data: Data, to targetURL: URL, backupURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: targetURL.path) {
            try? fileManager.removeItem(at: backupURL)
            try fileManager.copyItem(at: targetURL, to: backupURL)
        }
        // Data.atomic 会先写临时文件，再以原子替换方式发布新版本。
        try data.write(to: targetURL, options: [.atomic])
    }
}
