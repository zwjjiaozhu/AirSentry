import Foundation

struct MemoryInfo: Equatable {
    var totalBytes: UInt64
    var usedBytes: UInt64
    var freeBytes: UInt64
    var pressureLevel: MemoryPressureLevel

    var usageRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    static let empty = MemoryInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0, pressureLevel: .normal)
}

enum MemoryPressureLevel: Equatable {
    case normal
    case warning
    case critical

    var title: String {
        switch self {
        case .normal: "正常"
        case .warning: "警告"
        case .critical: "严重"
        }
    }

    var symbolName: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}
