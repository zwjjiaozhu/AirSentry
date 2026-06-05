import Foundation

enum ThermalLevel: String, CaseIterable, Identifiable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nominal: "正常"
        case .fair: "偏热"
        case .serious: "高温"
        case .critical: "严重高温"
        case .unknown: "未知"
        }
    }

    var shortTitle: String {
        switch self {
        case .nominal: "正常"
        case .fair: "偏热"
        case .serious: "高温"
        case .critical: "危险"
        case .unknown: "未知"
        }
    }

    var symbolName: String {
        switch self {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        case .serious: "thermometer.high"
        case .critical: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var severity: Int {
        switch self {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        case .unknown: -1
        }
    }
}
