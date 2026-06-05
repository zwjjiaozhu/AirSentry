import Foundation

enum ByteFormatter {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter
    }()

    static func string(from bytes: UInt64) -> String {
        formatter.string(fromByteCount: Int64(bytes))
    }

    static func speedString(from bytesPerSecond: Double) -> String {
        let value = max(bytesPerSecond, 0)
        return "\(formatter.string(fromByteCount: Int64(value)))/s"
    }
}
