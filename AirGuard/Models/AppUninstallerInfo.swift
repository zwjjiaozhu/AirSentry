import Foundation

struct InstalledAppInfo: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let version: String?
    let url: URL
    var bytes: UInt64
    let lastUsedAt: Date?
    let isSystemApp: Bool

    var displayVersion: String {
        guard let version, !version.isEmpty else { return "未知版本" }
        return version
    }
}

struct AppUninstallArtifact: Identifiable, Equatable {
    let id: String
    let url: URL
    let displayPath: String
    let kind: AppUninstallArtifactKind
    let risk: AppUninstallRisk
    let bytes: UInt64
    let isAccessible: Bool

    var isRecommended: Bool {
        risk != .high && isAccessible
    }
}

enum AppUninstallArtifactKind: String, CaseIterable {
    case application = "应用本体"
    case support = "应用数据"
    case cache = "缓存"
    case preferences = "偏好设置"
    case logs = "日志"
    case savedState = "窗口状态"
    case container = "容器数据"
    case groupContainer = "群组容器"
}

enum AppUninstallRisk: String {
    case low = "低风险"
    case medium = "需确认"
    case high = "高风险"

    var systemImage: String {
        switch self {
        case .low:
            return "checkmark.circle"
        case .medium:
            return "exclamationmark.triangle"
        case .high:
            return "hand.raised"
        }
    }
}

struct AppUninstallPlan: Equatable {
    let app: InstalledAppInfo
    let artifacts: [AppUninstallArtifact]

    var totalBytes: UInt64 {
        artifacts.reduce(0) { $0 + $1.bytes }
    }
}
