import Foundation

/// 通用日志归档写入器
/// 职责单一：接收日志文本，写入文件，按大小轮转，自动清理旧文件
/// 日志路径：~/Library/Logs/AirSentry/<prefix>-<timestamp>.log
final class LogArchiver {
    /// 单个日志文件大小上限（默认 2 MB）
    private let maxFileSizeBytes: UInt64 = 2 * 1024 * 1024
    /// 最多保留日志文件数
    private let maxLogFiles: Int
    /// 文件名前缀
    private let filePrefix: String

    private let logDirectory: URL

    private let fileTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// - Parameters:
    ///   - filePrefix: 日志文件名前缀，如 "thermal"
    ///   - subdirectory: Logs 下的子目录名，如 "AirSentry"
    ///   - maxLogFiles: 最多保留文件数
    init(filePrefix: String, subdirectory: String = "AirSentry", maxLogFiles: Int = 50) {
        self.filePrefix = filePrefix
        self.maxLogFiles = maxLogFiles

        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        logDirectory = logsDir.appendingPathComponent("Logs/\(subdirectory)", isDirectory: true)
        ensureLogDirectory()
    }

    // MARK: - Public API

    /// 写入一条日志。调用方自行决定何时写、写什么内容。
    func write(_ message: String) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            self.appendToFile(message)
            self.pruneOldLogs()
        }
    }

    /// 按修改时间倒序返回所有日志文件
    func listLogFiles() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "log" }
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
