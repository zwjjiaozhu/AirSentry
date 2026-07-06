import Foundation

/// 日志级别
enum LogLevel: String {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

/// 通用日志归档写入器
/// 职责单一：接收日志文本，写入文件，按大小轮转，自动清理旧文件
/// 日志路径：~/Library/Logs/AirSentry/<prefix>-<timestamp>.log
///
/// 统一日志格式：
/// 2026-07-06 14:30:15.123 [AirGuard] [INFO] [MonitorStore.swift:138] message content
final class LogArchiver {

    /// 全局共享实例，统一写入 air-sentry-<timestamp>.log
    static let shared = LogArchiver(filePrefix: "air-sentry", maxLogFiles: 20)

    /// 单个日志文件大小上限（默认 2 MB）
    private let maxFileSizeBytes: UInt64 = 2 * 1024 * 1024
    /// 最多保留日志文件数
    private let maxLogFiles: Int
    /// 文件名前缀
    private let filePrefix: String
    /// 进程标识（显示在每条日志中）
    private let process: String

    private let logDirectory: URL

    private let fileTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private let logLineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// - Parameters:
    ///   - filePrefix: 日志文件名前缀，如 "thermal"
    ///   - process: 进程标识，如 "AirGuard" 或 "FinderExt"
    ///   - subdirectory: Logs 下的子目录名，如 "AirSentry"
    ///   - maxLogFiles: 最多保留文件数
    init(filePrefix: String, process: String = "AirGuard", subdirectory: String = "AirSentry", maxLogFiles: Int = 50) {
        self.filePrefix = filePrefix
        self.process = process
        self.maxLogFiles = maxLogFiles

        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        logDirectory = logsDir.appendingPathComponent("Logs/\(subdirectory)", isDirectory: true)
        ensureLogDirectory()
    }

    // MARK: - Public API

    /// 写入 INFO 级别日志
    func info(_ message: String, file: String = #file, line: Int = #line) {
        write(message, level: .info, file: file, line: line)
    }

    /// 写入 WARNING 级别日志
    func warning(_ message: String, file: String = #file, line: Int = #line) {
        write(message, level: .warning, file: file, line: line)
    }

    /// 写入 ERROR 级别日志
    func error(_ message: String, file: String = #file, line: Int = #line) {
        write(message, level: .error, file: file, line: line)
    }

    /// 写入一条带级别的日志。
    func write(_ message: String, level: LogLevel = .info, file: String = #file, line: Int = #line) {
        let timestamp = logLineFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let formatted = "\(timestamp) [\(process)] [\(level.rawValue)] [\(fileName):\(line)] \(message)\n"
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            self.appendToFile(formatted)
            self.pruneOldLogs()
        }
    }

    /// 按修改时间倒序返回本实例的日志文件（仅匹配 filePrefix）
    func listLogFiles() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix(filePrefix) }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    /// 读取最新一个日志文件的内容
    func readLatestLogs() -> String {
        guard let latest = listLogFiles().first else { return "" }
        return (try? String(contentsOf: latest, encoding: .utf8)) ?? ""
    }

    /// 清理全部日志
    func clearAllLogs() {
        try? FileManager.default.removeItem(at: logDirectory)
        ensureLogDirectory()
    }

    // MARK: - Private

    private func appendToFile(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }

        let fileURL = currentLogFileURL()
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: fileURL)
        }
    }

    /// 获取当前应写入的日志文件 URL
    /// 最新文件未超限则继续追加，否则创建新文件
    private func currentLogFileURL() -> URL {
        if let latest = listLogFiles().first,
           let attrs = try? FileManager.default.attributesOfItem(atPath: latest.path),
           let size = attrs[.size] as? UInt64,
           size < maxFileSizeBytes {
            return latest
        }
        return createNewLogFile()
    }

    private func createNewLogFile() -> URL {
        let timestamp = fileTimestampFormatter.string(from: Date())
        let fileName = "\(filePrefix)-\(timestamp).log"
        let fileURL = logDirectory.appendingPathComponent(fileName)
        // 写入文件头，确保文件非空且便于识别
        let header = "# AirSentry \(filePrefix) log\n# Created: \(timestamp)\n\n"
        try? header.data(using: .utf8)?.write(to: fileURL)
        return fileURL
    }

    private func ensureLogDirectory() {
        if !FileManager.default.fileExists(atPath: logDirectory.path) {
            try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }
    }

    private func pruneOldLogs() {
        let files = listLogFiles()
        guard files.count > maxLogFiles else { return }
        for file in files.suffix(from: maxLogFiles) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
