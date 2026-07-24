import Foundation
import AppKit

/// Shell 命令的一次完整执行结果。
struct ShellResult: Sendable {
    /// 标准输出内容。
    let output: String

    /// 标准错误内容，启动失败时也会写入此字段。
    let error: String

    /// 子进程退出码，启动失败时固定为 1。
    let exitCode: Int
}

/// 持续排空单个 Pipe，并仅保留指定上限内的数据。
private final class BoundedOutputCapture: @unchecked Sendable {
    /// 每次读取的数据块大小，避免大输出产生过多临时对象。
    private static let chunkSize = 16 * 1024

    /// 被读取的文件句柄。
    private let handle: FileHandle

    /// 允许保留的最大字节数。
    private let byteLimit: Int

    /// 上限范围内已经保留的数据。
    private var retainedData = Data()

    /// 因超过上限而被省略的字节数。
    private var omittedByteCount = 0

    /// 创建一个有界输出读取器。
    /// - Parameters:
    ///   - handle: 要持续读取到 EOF 的文件句柄。
    ///   - byteLimit: 最多保留的输出字节数。
    init(handle: FileHandle, byteLimit: Int) {
        self.handle = handle
        self.byteLimit = max(byteLimit, 0)
    }

    /// 持续读取文件句柄直到 EOF，超过上限的数据仍会被排空但不再保留。
    func drain() {
        while true {
            do {
                guard let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else { break }

                // 即使达到保留上限也继续读取，防止子进程因 Pipe 写满而阻塞。
                let remainingCapacity = max(byteLimit - retainedData.count, 0)
                if remainingCapacity > 0 {
                    retainedData.append(contentsOf: chunk.prefix(remainingCapacity))
                }
                omittedByteCount += max(chunk.count - remainingCapacity, 0)
            } catch {
                break
            }
        }
    }

    /// 将已保留数据转换为字符串，并在发生截断时附加说明。
    /// - Returns: UTF-8 输出文本及可选的截断提示。
    func renderedString() -> String {
        var text = String(decoding: retainedData, as: UTF8.self)
        if omittedByteCount > 0 {
            if !text.isEmpty, !text.hasSuffix("\n") {
                text.append("\n")
            }
            text.append("[输出已截断，省略 \(omittedByteCount) 字节]\n")
        }
        return text
    }
}

enum Shell {
    /// 通过 `/bin/sh -c` 同步执行命令，并安全地并发排空标准输出和标准错误。
    /// - Parameters:
    ///   - command: 要交给 shell 执行的完整命令字符串。
    ///   - currentDirectory: 子进程工作目录；为 nil 时继承当前进程目录。
    ///   - outputLimit: 标准输出与标准错误各自最多保留的字节数。
    /// - Returns: 包含输出、错误与退出码的执行结果。
    static func run(
        _ command: String,
        currentDirectory: URL? = nil,
        outputLimit: Int = 1_000_000
    ) -> ShellResult {
        run(
            executable: "/bin/sh",
            arguments: ["-c", command],
            currentDirectory: currentDirectory,
            outputLimit: outputLimit
        )
    }

    /// 直接执行指定程序，避免无需 shell 时的字符串转义与注入风险。
    /// - Parameters:
    ///   - executable: 可执行文件的绝对路径。
    ///   - arguments: 原样传给可执行文件的参数数组。
    ///   - currentDirectory: 子进程工作目录；为 nil 时继承当前进程目录。
    ///   - outputLimit: 标准输出与标准错误各自最多保留的字节数。
    /// - Returns: 包含输出、错误与退出码的执行结果。
    static func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        outputLimit: Int = 1_000_000
    ) -> ShellResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let retainedByteLimit = max(outputLimit, 0)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            return ShellResult(output: "", error: error.localizedDescription, exitCode: 1)
        }

        let outputCapture = BoundedOutputCapture(
            handle: standardOutput.fileHandleForReading,
            byteLimit: retainedByteLimit
        )
        let errorCapture = BoundedOutputCapture(
            handle: standardError.fileHandleForReading,
            byteLimit: retainedByteLimit
        )
        let readers = DispatchGroup()

        // 两个 Pipe 必须同时读取，否则任意一侧写满都可能阻塞子进程。
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputCapture.drain()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorCapture.drain()
            readers.leave()
        }

        process.waitUntilExit()
        readers.wait()

        return ShellResult(
            output: outputCapture.renderedString(),
            error: errorCapture.renderedString(),
            exitCode: Int(process.terminationStatus)
        )
    }

    /// 在独立任务中执行 shell 命令，避免阻塞 MainActor。
    /// - Parameters:
    ///   - command: 要交给 shell 执行的完整命令字符串。
    ///   - currentDirectory: 子进程工作目录；为 nil 时继承当前进程目录。
    ///   - outputLimit: 标准输出与标准错误各自最多保留的字节数。
    /// - Returns: 包含输出、错误与退出码的执行结果。
    static func runInBackground(
        _ command: String,
        currentDirectory: URL? = nil,
        outputLimit: Int = 1_000_000
    ) async -> ShellResult {
        await Task.detached(priority: .userInitiated) {
            run(command, currentDirectory: currentDirectory, outputLimit: outputLimit)
        }.value
    }

    /// 在独立任务中直接执行程序，避免阻塞 MainActor。
    /// - Parameters:
    ///   - executable: 可执行文件的绝对路径。
    ///   - arguments: 原样传给可执行文件的参数数组。
    ///   - currentDirectory: 子进程工作目录；为 nil 时继承当前进程目录。
    ///   - outputLimit: 标准输出与标准错误各自最多保留的字节数。
    /// - Returns: 包含输出、错误与退出码的执行结果。
    static func runInBackground(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        outputLimit: Int = 1_000_000
    ) async -> ShellResult {
        await Task.detached(priority: .userInitiated) {
            run(
                executable: executable,
                arguments: arguments,
                currentDirectory: currentDirectory,
                outputLimit: outputLimit
            )
        }.value
    }
}

extension String {
    /// 将字符串包装成可安全嵌入 shell 命令的单引号参数。
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// 将字符串写入系统剪贴板。
/// - Parameter string: 要复制的完整文本。
/// - Returns: 系统剪贴板是否成功接收文本。
@discardableResult
func copyToPasteboard(_ string: String) -> Bool {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.setString(string, forType: .string)
}
